import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import '../../models/direct_message.dart';
import '../../services/default_group_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/browser_storage.dart';
import '../../services/invitation_service.dart';
import '../../services/postcode_service.dart';
import '../../services/dm_service.dart';
import '../../services/saved_message_service.dart';
import '../../models/saved_message.dart';

// ── Design tokens — aliases to the single source of truth (HuddlColors) ─────
const Color _kOnline = Color(0xFF34C759);

// ── Cambridge-area image assets (same pool as DefaultGroupService) ────────
const List<String> _cambridgeImages = [
  'assets/images/groups/cambridge_kings_college.jpg',
  'assets/images/groups/cambridge_punting.jpg',
  'assets/images/groups/cambridge_trinity.jpg',
  'assets/images/groups/cambridge_the_backs.jpg',
  'assets/images/groups/cambridge_river_boats.jpg',
  'assets/images/groups/east_cambs_ely_cathedral.jpg',
  'assets/images/groups/south_cambs_village.jpg',
];

// ── Persistence key for user-created groups ──────────────────────────────
const String _userGroupsKey = 'user_created_groups_v1';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Shared notifier: increment to tell tabs to reload user-created groups.
  final ValueNotifier<int> _groupsChangedNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // rebuild to show/hide header icons per tab
      }
    });
  }

  @override
  void dispose() {
    _groupsChangedNotifier.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Navigate to Create Group, and when the user returns, signal both tabs.
  Future<void> _openCreateGroup() async {
    final result = await Navigator.pushNamed(context, '/create_group');
    // If a group was created (result is non-null), notify tabs to reload
    if (result != null) {
      _groupsChangedNotifier.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MyHuddl',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Tab bar ───────────────────────────────────────
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Messages'),
                      Tab(text: 'Discover'),
                      Tab(text: 'Saved'),
                    ],
                    labelColor: HuddlColors.primary,
                    unselectedLabelColor: HuddlColors.textHint,
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    indicatorColor: HuddlColors.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: HuddlColors.divider,
                  ),
                ],
              ),
            ),
            // ── Tab content ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MessagesTab(groupsChangedNotifier: _groupsChangedNotifier),
                  _DiscoverTab(groupsChangedNotifier: _groupsChangedNotifier),
                  _SavedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGES TAB — loads default groups from DefaultGroupService + user groups
// ═══════════════════════════════════════════════════════════════════════════════

class _MessagesTab extends StatefulWidget {
  final ValueNotifier<int> groupsChangedNotifier;
  const _MessagesTab({required this.groupsChangedNotifier});

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  final DefaultGroupService _groupService = DefaultGroupService();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final InvitationService _invitationService = InvitationService();
  final DMService _dmService = DMService();

  List<_GroupItem> _allGroups = [];
  List<_GroupItem> _filteredGroups = [];
  List<GroupInvitation> _pendingInvitations = [];
  List<DMConversation> _dmConversations = [];
  List<DMConversation> _filteredDMs = [];
  final Set<String> _pinnedGroupIds = {};
  final Set<String> _mutedGroupIds = {};
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _dmService.addListener(_onDMUpdate);
    widget.groupsChangedNotifier.addListener(_onGroupsChanged);
  }

  @override
  void dispose() {
    widget.groupsChangedNotifier.removeListener(_onGroupsChanged);
    _searchController.dispose();
    _dmService.removeListener(_onDMUpdate);
    super.dispose();
  }

  void _onGroupsChanged() {
    _loadGroups();
  }

  void _onDMUpdate() {
    if (mounted) {
      setState(() {
        _dmConversations = List.from(_dmService.conversations);
        _applyFilter();
      });
    }
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      // Ensure all services have loaded their persisted data
      await _onboardingService.initialize();
      await _groupService.initialize();
      await _invitationService.initialize();
      await _dmService.initialize();

      // Load DM conversations
      _dmConversations = List.from(_dmService.conversations);

      // ── 1. Try to get previously assigned default groups ──────────
      List<Group> defaultGroups =
          await _groupService.getUserGroups('current_user');

      // ── 2. If none, try to assign now based on onboarding data ──
      if (defaultGroups.isEmpty) {
        defaultGroups =
            await _groupService.assignUserToDefaultGroups('current_user');
      }

      // ── 3. Last resort: re-join existing defaults ─────────────────
      if (defaultGroups.isEmpty) {
        final allDefaults = _groupService.getAllDefaultGroups();
        if (allDefaults.isNotEmpty) {
          for (final g in allDefaults) {
            _groupService.joinGroup('current_user', g.id);
          }
          defaultGroups = await _groupService.getUserGroups('current_user');
        }
      }

      // ── User-created groups (from local storage) ────────────────
      final userGroupsJson = await BrowserStorage.getString(_userGroupsKey);
      List<Group> userGroups = [];
      if (userGroupsJson != null) {
        final List<dynamic> decoded = json.decode(userGroupsJson);
        userGroups =
            decoded.map((j) => Group.fromJson(j as Map<String, dynamic>)).toList();
      }

      // ── Merge into _GroupItem list ─────────────────────────────
      final List<_GroupItem> items = [];

      for (final g in defaultGroups) {
        items.add(_GroupItem.fromGroup(g, isDefault: true));
      }
      for (final g in userGroups) {
        if (!items.any((i) => i.id == g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: false));
        }
      }

      // ── Joined public groups (from Discover) ─────────────────────
      for (final g in _invitationService.joinedGroups) {
        if (!items.any((i) => i.id == g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: false));
        }
      }

      // ── Accepted invitations → become private group entries ──────
      for (final inv in _invitationService.acceptedInvitations) {
        if (!items.any((i) => i.id == inv.groupId)) {
          items.add(_GroupItem(
            id: inv.groupId,
            name: inv.groupName,
            description: inv.groupDescription,
            imageUrl: inv.groupImageUrl,
            memberCount: 0,
            category: 'PRIVATE',
            isDefault: false,
            isImageLocked: false,
            isPrivate: true,
            lastMessage: '${inv.invitedByName}: Welcome to the group!',
            lastSenderName: inv.invitedByName,
            lastMessageTime: inv.sentAt,
            unreadCount: 1,
          ));
        }
      }

      // If nothing, show demo items
      if (items.isEmpty) {
        items.addAll(_demoCommunityGroups());
      }

      setState(() {
        _allGroups = items;
        _pendingInvitations = _invitationService.pendingInvitations;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      // Fallback to demo items
      setState(() {
        _allGroups = _demoCommunityGroups();
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredGroups = List.from(_allGroups);
      _filteredDMs = List.from(_dmConversations);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredGroups = _allGroups
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              (g.lastMessage ?? '').toLowerCase().contains(q))
          .toList();
      _filteredDMs = _dmConversations
          .where((d) =>
              d.recipientName.toLowerCase().contains(q) ||
              (d.lastMessage ?? '').toLowerCase().contains(q))
          .toList();
    }
    // Sort: pinned first, then by last message time descending
    _filteredGroups.sort((a, b) {
      final aPinned = _pinnedGroupIds.contains(a.id);
      final bPinned = _pinnedGroupIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return (b.lastMessageTime ?? DateTime(2000))
          .compareTo(a.lastMessageTime ?? DateTime(2000));
    });
  }

  /// Build a unified list of items (groups + DMs) sorted by most recent
  /// message time — just like WhatsApp.
  List<_MessageListItem> get _unifiedMessageList {
    final List<_MessageListItem> items = [];

    for (final g in _filteredGroups) {
      items.add(_MessageListItem(
        id: g.id,
        name: g.name,
        imageUrl: g.imageUrl,
        lastMessage: g.lastMessage,
        lastSenderName: g.lastSenderName,
        lastMessageTime: g.lastMessageTime,
        unreadCount: g.unreadCount ?? 0,
        isGroup: true,
        isPinned: _pinnedGroupIds.contains(g.id),
        isMuted: _mutedGroupIds.contains(g.id),
        isPrivate: g.isPrivate,
        groupItem: g,
        isTyping: false,
      ));
    }

    for (final dm in _filteredDMs) {
      items.add(_MessageListItem(
        id: dm.id,
        name: dm.recipientName,
        imageUrl: '',
        avatarColor: dm.recipientAvatarColor,
        lastMessage: dm.lastMessage,
        lastSenderName: dm.lastSenderName,
        lastMessageTime: dm.lastMessageTime,
        unreadCount: dm.unreadCount,
        isGroup: false,
        isPinned: _pinnedGroupIds.contains(dm.id),
        isMuted: _mutedGroupIds.contains(dm.id),
        isPrivate: false,
        dmConversation: dm,
        isTyping: dm.isTyping,
      ));
    }

    // Sort: pinned first, then by last message time descending
    items.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return (b.lastMessageTime ?? DateTime(2000))
          .compareTo(a.lastMessageTime ?? DateTime(2000));
    });

    return items;
  }

  // ── Long-press actions ─────────────────────────────────────────────────
  void _showGroupActions(BuildContext ctx, _GroupItem group) {
    final isPinned = _pinnedGroupIds.contains(group.id);
    final isMuted = _mutedGroupIds.contains(group.id);

    showModalBottomSheet(
      context: ctx,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: isPinned ? 'Unpin' : 'Pin',
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    if (isPinned) {
                      _pinnedGroupIds.remove(group.id);
                    } else {
                      _pinnedGroupIds.add(group.id);
                    }
                    _applyFilter();
                  });
                },
              ),
              _ActionTile(
                icon: isMuted
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                label: isMuted ? 'Unmute' : 'Mute',
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    if (isMuted) {
                      _mutedGroupIds.remove(group.id);
                    } else {
                      _mutedGroupIds.add(group.id);
                    }
                  });
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                          isMuted ? '${group.name} unmuted' : '${group.name} muted'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              _ActionTile(
                icon: (group.unreadCount ?? 0) > 0
                    ? Icons.mark_chat_read_outlined
                    : Icons.mark_chat_unread_outlined,
                label: (group.unreadCount ?? 0) > 0
                    ? 'Mark as read'
                    : 'Mark as unread',
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    final idx = _allGroups.indexWhere((g) => g.id == group.id);
                    if (idx != -1) {
                      final current = _allGroups[idx].unreadCount ?? 0;
                      _allGroups[idx] = _allGroups[idx].copyWith(
                        unreadCount: current > 0 ? 0 : 1,
                      );
                      _applyFilter();
                    }
                  });
                },
              ),
              _ActionTile(
                icon: Icons.archive_outlined,
                label: 'Archive',
                onTap: () {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('${group.name} archived')),
                  );
                },
              ),
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(c);
                  final listItem = _MessageListItem(
                    id: group.id,
                    name: group.name,
                    imageUrl: group.imageUrl,
                    lastMessage: group.lastMessage,
                    lastSenderName: group.lastSenderName,
                    lastMessageTime: group.lastMessageTime,
                    unreadCount: group.unreadCount ?? 0,
                    isGroup: true,
                    isPinned: isPinned,
                    isMuted: isMuted,
                    isPrivate: group.isPrivate,
                    groupItem: group,
                    isTyping: false,
                  );
                  _confirmDeleteConversation(ctx, listItem);
                },
              ),
              _ActionTile(
                icon: Icons.exit_to_app,
                label: 'Leave group',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(c);
                  _confirmLeaveGroup(ctx, group);
                },
              ),
              const SizedBox(height: 4),
              const Divider(height: 1, color: HuddlColors.divider),
              _ActionTile(
                icon: Icons.close,
                label: 'Cancel',
                onTap: () => Navigator.pop(c),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmLeaveGroup(BuildContext ctx, _GroupItem group) {
    showDialog(
      context: ctx,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sad face icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sentiment_dissatisfied_outlined,
                    size: 32, color: Colors.red),
              ),
              const SizedBox(height: 18),
              Text(
                'Leave this group?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: HuddlColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We are sad to see you go, but you can always come back or find another group that interests you in the Discover tab.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: HuddlColors.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: HuddlColors.divider,
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final onboarding = OnboardingDataService();
                        await onboarding.initialize();
                        final userName = onboarding.name ?? 'You';

                        await _invitationService.leaveGroup(group.id, userName);
                        await _removeFromUserCreatedGroups(group.id);

                        setState(() {
                          _allGroups.removeWhere((g) => g.id == group.id);
                          _applyFilter();
                        });
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Left ${group.name}'),
                              backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Leave',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
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

  Future<void> _removeFromUserCreatedGroups(String groupId) async {
    try {
      final raw = await BrowserStorage.getString(_userGroupsKey);
      if (raw == null) return;
      final List<dynamic> groups = json.decode(raw);
      groups.removeWhere((j) => (j as Map<String, dynamic>)['id'] == groupId);
      await BrowserStorage.setString(_userGroupsKey, json.encode(groups));
    } catch (_) {
      // silently fail
    }
  }

  // ── Invitation handlers ──────────────────────────────────────────────
  Future<void> _handleAccept(GroupInvitation inv) async {
    await _invitationService.acceptInvitation(inv.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined ${inv.groupName}!'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      // Reload everything so the group appears in the messages list
      await _loadGroups();
    }
  }

  Future<void> _handleDecline(GroupInvitation inv) async {
    await _invitationService.declineInvitation(inv.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Declined invite to ${inv.groupName}'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      setState(() {
        _pendingInvitations.removeWhere((i) => i.id == inv.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: HuddlColors.primary),
      );
    }

    final unified = _unifiedMessageList;

    return Stack(
      children: [
        Column(
          children: [
            // ── Collapsible search bar ──────────────────────────────────
            if (_showSearch)
              Container(
                color: HuddlColors.white,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: HuddlSearchBar(
                        hint: 'Search messages & DMs...',
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                            _applyFilter();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showSearch = false;
                          _searchQuery = '';
                          _searchController.clear();
                          _applyFilter();
                        });
                      },
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              color: HuddlColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),

            // ── Unified message list (groups + DMs) ──────────────────
            Expanded(
              child: (unified.isEmpty && _pendingInvitations.isEmpty)
                  ? _EmptyMessagesState(onSearch: () {
                      setState(() => _showSearch = true);
                    })
                  : RefreshIndicator(
                      onRefresh: _loadGroups,
                      color: HuddlColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 100),
                        children: [
                          // ── Pending invitation cards ──────────────────────
                          if (_pendingInvitations.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                'Group invitations',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.textHint,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            ..._pendingInvitations.map((inv) => _InvitationCard(
                                  invitation: inv,
                                  onAccept: () => _handleAccept(inv),
                                  onDecline: () => _handleDecline(inv),
                                )),
                            const Divider(height: 1, color: HuddlColors.divider),
                            const SizedBox(height: 4),
                          ],
                          // ── Unified rows (groups + DMs, sorted by recent) ──
                          ...unified.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;

                            final bool isUnread = item.unreadCount > 0;

                            Widget rowWidget;
                            if (item.isGroup) {
                              rowWidget = _GroupMessageRow(
                                group: item.groupItem!,
                                isPinned: item.isPinned,
                                isMuted: item.isMuted,
                                onTap: () {
                                  Navigator.pushNamed(context, '/group_chat',
                                      arguments: {
                                        'groupId': item.groupItem!.id,
                                        'groupName': item.groupItem!.name,
                                        'groupImageUrl': item.groupItem!.imageUrl,
                                      });
                                },
                                onLongPress: () =>
                                    _showGroupActions(context, item.groupItem!),
                              );
                            } else {
                              rowWidget = _DMMessageRow(
                                conversation: item.dmConversation!,
                                isPinned: item.isPinned,
                                isMuted: item.isMuted,
                                onTap: () {
                                  Navigator.pushNamed(context, '/dm_chat',
                                      arguments: {
                                        'recipientId': item.dmConversation!.recipientId,
                                        'recipientName': item.dmConversation!.recipientName,
                                        'recipientAvatarColor':
                                            item.dmConversation!.recipientAvatarColor,
                                        'conversationId': item.dmConversation!.id,
                                      });
                                },
                                onLongPress: () =>
                                    _showDMActions(context, item.dmConversation!),
                              );
                            }

                            return Column(
                              children: [
                                _SwipeActionRow(
                                  key: ValueKey('swipe_${item.id}'),
                                  isUnread: isUnread,
                                  onDelete: () => _confirmDeleteConversation(context, item),
                                  onToggleRead: () => _toggleReadStatus(item),
                                  child: rowWidget,
                                ),
                                if (index < unified.length - 1)
                                  const Divider(
                                    height: 1,
                                    indent: 80,
                                    color: HuddlColors.divider,
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
            ),
          ],
        ),

        // ── FAB for new DM ──────────────────────────────────────────
        Positioned(
          bottom: 24,
          right: 16,
          child: Material(
            elevation: 6,
            shadowColor: HuddlColors.primary.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            color: HuddlColors.primary,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/new_dm'),
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Toggle read / unread state ────────────────────────────────────────
  void _toggleReadStatus(_MessageListItem item) {
    if (item.isGroup) {
      // Group: toggle unread on local _allGroups list
      final idx = _allGroups.indexWhere((g) => g.id == item.id);
      if (idx != -1) {
        final current = _allGroups[idx].unreadCount ?? 0;
        setState(() {
          _allGroups[idx] = _allGroups[idx].copyWith(
            unreadCount: current > 0 ? 0 : 1,
          );
          _applyFilter();
        });
      }
    } else {
      // DM: use the service so it persists
      if (item.unreadCount > 0) {
        _dmService.markConversationRead(item.id);
      } else {
        _dmService.markConversationUnread(item.id);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.unreadCount > 0
                ? '${item.name} marked as read'
                : '${item.name} marked as unread',
          ),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Delete conversation confirmation dialog ──────────────────────────
  void _confirmDeleteConversation(BuildContext ctx, _MessageListItem item) {
    showDialog(
      context: ctx,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to permanently delete this conversation?',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.textDark,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: HuddlColors.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: HuddlColors.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        if (item.isGroup) {
                          await _removeFromUserCreatedGroups(item.id);
                          setState(() {
                            _allGroups.removeWhere((g) => g.id == item.id);
                            _applyFilter();
                          });
                        } else {
                          await _dmService.deleteConversation(item.id);
                          setState(() {
                            _dmConversations.removeWhere((d) => d.id == item.id);
                            _applyFilter();
                          });
                        }
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('${item.name} deleted'),
                              backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Delete',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
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

  // ── DM long-press actions ───────────────────────────────────────────────
  void _showDMActions(BuildContext ctx, DMConversation dm) {
    final isPinned = _pinnedGroupIds.contains(dm.id);
    final isMuted = _mutedGroupIds.contains(dm.id);
    final isUnread = dm.unreadCount > 0;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: isPinned ? 'Unpin' : 'Pin',
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    if (isPinned) {
                      _pinnedGroupIds.remove(dm.id);
                    } else {
                      _pinnedGroupIds.add(dm.id);
                    }
                    _applyFilter();
                  });
                },
              ),
              _ActionTile(
                icon: isMuted
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                label: isMuted ? 'Unmute' : 'Mute',
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    if (isMuted) {
                      _mutedGroupIds.remove(dm.id);
                    } else {
                      _mutedGroupIds.add(dm.id);
                    }
                  });
                },
              ),
              _ActionTile(
                icon: isUnread
                    ? Icons.mark_chat_read_outlined
                    : Icons.mark_chat_unread_outlined,
                label: isUnread ? 'Mark as read' : 'Mark as unread',
                onTap: () async {
                  Navigator.pop(c);
                  if (isUnread) {
                    await _dmService.markConversationRead(dm.id);
                  } else {
                    await _dmService.markConversationUnread(dm.id);
                  }
                },
              ),
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(c);
                  final listItem = _MessageListItem(
                    id: dm.id,
                    name: dm.recipientName,
                    imageUrl: '',
                    lastMessage: dm.lastMessage,
                    lastSenderName: dm.lastSenderName,
                    lastMessageTime: dm.lastMessageTime,
                    unreadCount: dm.unreadCount,
                    isGroup: false,
                    isPinned: isPinned,
                    isMuted: isMuted,
                    isPrivate: false,
                    dmConversation: dm,
                    isTyping: dm.isTyping,
                  );
                  _confirmDeleteConversation(ctx, listItem);
                },
              ),
              const SizedBox(height: 4),
              const Divider(height: 1, color: HuddlColors.divider),
              _ActionTile(
                icon: Icons.close,
                label: 'Cancel',
                onTap: () => Navigator.pop(c),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Demo community groups (fallback when no onboarding data) ───────────
  List<_GroupItem> _demoCommunityGroups() {
    return [
      _GroupItem(
        id: 'demo_cambridge_parents',
        name: '2021 Cambridge Parents',
        description:
            'Connect with parents in Cambridge whose children were born in 2021.',
        imageUrl: _cambridgeImages[0],
        memberCount: 42,
        category: 'Default Community',
        isDefault: true,
        isImageLocked: true,
        lastMessage: 'Emma: Has anyone tried the new park on Mill Road?',
        lastSenderName: 'Emma',
        lastMessageTime: DateTime.now().subtract(const Duration(minutes: 3)),
        unreadCount: 3,
      ),
      _GroupItem(
        id: 'demo_expecting_cambridge',
        name: 'Cambridge Expecting Parents',
        description:
            'For expecting parents in Cambridge preparing for their new arrival.',
        imageUrl: _cambridgeImages[1],
        memberCount: 28,
        category: 'Default Community',
        isDefault: true,
        isImageLocked: true,
        lastMessage: 'Sophie: Which hospital are you all going with?',
        lastSenderName: 'Sophie',
        lastMessageTime: DateTime.now().subtract(const Duration(minutes: 18)),
        unreadCount: 1,
      ),
      _GroupItem(
        id: 'demo_2019_cambridge',
        name: '2019 Cambridge Parents',
        description:
            'Parents with children born in 2019 in the Cambridge area.',
        imageUrl: _cambridgeImages[2],
        memberCount: 67,
        category: 'Default Community',
        isDefault: true,
        isImageLocked: true,
        lastMessage: 'Lucy: Reception class applications open next week!',
        lastSenderName: 'Lucy',
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 1)),
        unreadCount: 5,
      ),
      _GroupItem(
        id: 'demo_toddler_activities',
        name: 'Toddler Activities Cambridge',
        description: 'Share and discover toddler-friendly activities in Cambridge.',
        imageUrl: _cambridgeImages[3],
        memberCount: 156,
        category: 'Activities',
        isDefault: false,
        isImageLocked: false,
        lastMessage: 'Kate: Storytime at the library is brilliant on Tuesdays',
        lastSenderName: 'Kate',
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 2)),
        unreadCount: 0,
      ),
      _GroupItem(
        id: 'demo_baby_sleep',
        name: 'Baby Sleep Support',
        description: 'Support group for parents navigating baby sleep challenges.',
        imageUrl: _cambridgeImages[4],
        memberCount: 89,
        category: 'Support',
        isDefault: false,
        isImageLocked: false,
        lastMessage: 'Anna: We finally got 6 hours straight!',
        lastSenderName: 'Anna',
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 4)),
        unreadCount: 0,
      ),
      _GroupItem(
        id: 'demo_south_cambs',
        name: 'South Cambridgeshire Parents',
        description: 'Parents living in the South Cambridgeshire villages.',
        imageUrl: _cambridgeImages[6],
        memberCount: 34,
        category: 'Default Community',
        isDefault: true,
        isImageLocked: true,
        lastMessage: 'James: Village fete this Saturday - anyone going?',
        lastSenderName: 'James',
        lastMessageTime: DateTime.now().subtract(const Duration(hours: 6)),
        unreadCount: 0,
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP MESSAGE ROW — scenic photo avatar, unread badge, online dot, pin icon
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupMessageRow extends StatelessWidget {
  final _GroupItem group;
  final bool isPinned;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GroupMessageRow({
    required this.group,
    required this.isPinned,
    required this.isMuted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = (group.unreadCount ?? 0) > 0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isPinned ? const Color(0xFFFFF8F0) : HuddlColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── Group avatar (scenic image or fallback) ──────────
            _GroupAvatar(
              imageUrl: group.imageUrl,
              size: 54,
              isOnline: hasUnread, // show green dot when there's activity
            ),
            const SizedBox(width: 12),

            // ── Name + last message ─────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Pin icon
                      if (isPinned) ...[
                        Icon(Icons.push_pin,
                            size: 14, color: HuddlColors.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight:
                                      hasUnread ? FontWeight.w600 : FontWeight.w500,
                                  color: HuddlColors.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (group.isPrivate) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: HuddlColors.textHint.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Private Group',
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Mute icon
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.notifications_off,
                            size: 14, color: HuddlColors.textHint),
                      ],
                      const SizedBox(width: 6),
                      // Time
                      Text(
                        _formatTime(group.lastMessageTime),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: hasUnread ? HuddlColors.primary : HuddlColors.textHint,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.lastMessage ?? 'Tap to start a conversation',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: hasUnread ? HuddlColors.textSecondary : HuddlColors.textHint,
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${group.unreadCount}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INVITATION CARD — shown in Messages tab for pending group invitations
// ═══════════════════════════════════════════════════════════════════════════════

class _InvitationCard extends StatelessWidget {
  final GroupInvitation invitation;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InvitationCard({
    required this.invitation,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: HuddlColors.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: HuddlColors.peachLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.group_add, size: 24, color: HuddlColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            invitation.groupName,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Invite',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${invitation.invitedByName} invited you to join',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (invitation.groupDescription.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              invitation.groupDescription,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: HuddlColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: HuddlColors.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Decline',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      'Accept',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DM MESSAGE ROW — person avatar with online dot, typing, unread badge
// ═══════════════════════════════════════════════════════════════════════════════

class _DMMessageRow extends StatelessWidget {
  final DMConversation conversation;
  final bool isPinned;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DMMessageRow({
    required this.conversation,
    required this.isPinned,
    required this.isMuted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    final color = _dmColorFromHex(conversation.recipientAvatarColor);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isPinned ? const Color(0xFFFFF8F0) : HuddlColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── Person avatar ──────────────────────────────────
            Stack(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      conversation.recipientName.isNotEmpty
                          ? conversation.recipientName[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _kOnline,
                      shape: BoxShape.circle,
                      border: Border.all(color: HuddlColors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // ── Name + last message ─────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPinned) ...[
                        Icon(Icons.push_pin,
                            size: 14,
                            color: HuddlColors.primary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          conversation.recipientName,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w500,
                            color: HuddlColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.notifications_off,
                            size: 14, color: HuddlColors.textHint),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(conversation.lastMessageTime),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: hasUnread
                              ? HuddlColors.primary
                              : HuddlColors.textHint,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: conversation.isTyping
                            ? Text(
                                'typing...',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: HuddlColors.teal,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : Text(
                                conversation.lastMessage ??
                                    'Tap to start chatting',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: hasUnread
                                      ? HuddlColors.textSecondary
                                      : HuddlColors.textHint,
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

Color _dmColorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIFIED MESSAGE LIST ITEM — wraps either a group or a DM for sorting
// ═══════════════════════════════════════════════════════════════════════════════

class _MessageListItem {
  final String id;
  final String name;
  final String imageUrl;
  final String? avatarColor;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final bool isPinned;
  final bool isMuted;
  final bool isPrivate;
  final bool isTyping;
  final _GroupItem? groupItem;
  final DMConversation? dmConversation;

  _MessageListItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.avatarColor,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageTime,
    required this.unreadCount,
    required this.isGroup,
    required this.isPinned,
    required this.isMuted,
    required this.isPrivate,
    this.groupItem,
    this.dmConversation,
    this.isTyping = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP AVATAR — scenic image with online dot ─────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool isOnline;

  const _GroupAvatar({
    required this.imageUrl,
    this.size = 54,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: HuddlColors.peachLight,
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildImage(),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _kOnline,
                shape: BoxShape.circle,
                border: Border.all(color: HuddlColors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImage() {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    } else if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _fallbackIcon(),
      );
    } else if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(imageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (_, __, ___) => _fallbackIcon(),
          );
        }
      } catch (_) {
        // fall through
      }
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      color: HuddlColors.peachLight,
      child: Center(
        child: Icon(
          Icons.people,
          size: size * 0.45,
          color: HuddlColors.primary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISCOVER TAB — searchable group discovery with join, filter, sort, CTA & FAB
// ═══════════════════════════════════════════════════════════════════════════════

class _DiscoverTab extends StatefulWidget {
  final ValueNotifier<int> groupsChangedNotifier;
  const _DiscoverTab({required this.groupsChangedNotifier});

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String _selectedSort = 'Recommended';
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchField = false;

  // Onboarding profile — used for audience-based filtering and borough matching
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final InvitationService _invitationService = InvitationService();
  String? _userParentType;
  List<String> _userStagesOfLife = [];
  String? _userBorough;
  bool _profileLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    widget.groupsChangedNotifier.addListener(_onGroupsChanged);
  }

  @override
  void dispose() {
    widget.groupsChangedNotifier.removeListener(_onGroupsChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onGroupsChanged() {
    // Reload user-created groups when notified (e.g. after creating a group)
    _reloadUserCreatedGroups();
  }

  /// Reload only user-created public groups from storage and rebuild
  Future<void> _reloadUserCreatedGroups() async {
    // Remove previously loaded user-created groups (keep hardcoded ones)
    _allDiscoverGroups.removeWhere((g) => g.id.startsWith('user_'));
    await _loadUserCreatedGroups();
    if (mounted) setState(() {});
  }

  Future<void> _loadUserProfile() async {
    await _onboardingService.initialize();
    await _invitationService.initialize();
    // Also load any user-created public groups from local storage
    await _loadUserCreatedGroups();
    if (mounted) {
      setState(() {
        _userParentType = _onboardingService.parentType;
        _userStagesOfLife = _onboardingService.stagesOfLife;
        final postcode = _onboardingService.postcode;
        _userBorough = PostcodeService().getBoroughFromPostcode(postcode);
        _profileLoaded = true;
      });
    }
  }

  /// Load user-created groups from local storage and add public ones to
  /// the discover list so other users (in the demo) can see them.
  Future<void> _loadUserCreatedGroups() async {
    try {
      final raw = await BrowserStorage.getString(_userGroupsKey);
      if (raw == null) return;
      final List<dynamic> decoded = json.decode(raw);
      for (final j in decoded) {
        final g = Group.fromJson(j as Map<String, dynamic>);
        // Only add public groups; private groups never appear on Discover
        if (!g.isPrivate) {
          // Avoid duplicates
          if (!_allDiscoverGroups.any((d) => d.id == g.id)) {
            _allDiscoverGroups.add(_GroupItem.fromGroup(g, isDefault: false));
          }
        }
      }
    } catch (_) {
      // Silently ignore storage read failures
    }
  }

  final List<String> _filterLabels = [
    'All',
    'Parenting',
    'Health',
    'Activities',
    'Fitness',
    'Food',
    'Work-Life',
    'Sleep',
  ];

  final List<String> _sortOptions = [
    'Recommended',
    'Most Members',
    'Newest',
    'A-Z',
  ];

  final List<_GroupItem> _allDiscoverGroups = [
    _GroupItem(
      id: 'disc_first_time_mums',
      name: 'First Time Mums',
      description:
          'A supportive community for first-time mothers navigating the joys and challenges of new parenthood.',
      imageUrl:
          'https://images.pexels.com/photos/3242264/pexels-photo-3242264.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 1247,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
    ),
    _GroupItem(
      id: 'disc_dads_connect',
      name: 'Dads Connect',
      description:
          'A space for dads to share experiences, ask questions, and support each other.',
      imageUrl:
          'https://images.pexels.com/photos/1648387/pexels-photo-1648387.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 834,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Dads'],
    ),
    _GroupItem(
      id: 'disc_baby_sleep',
      name: 'Baby Sleep Solutions',
      description:
          'Tips, advice and support for getting your baby to sleep through the night.',
      imageUrl:
          'https://images.pexels.com/photos/971435/pexels-photo-971435.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 2156,
      category: 'SLEEP',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Parents expecting a baby'],
    ),
    _GroupItem(
      id: 'disc_healthy_meals',
      name: 'Healthy Family Meals',
      description:
          'Share recipes, meal plans and ideas for nutritious family-friendly meals.',
      imageUrl:
          'https://images.pexels.com/photos/5082869/pexels-photo-5082869.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 1589,
      category: 'FOOD & NUTRITION',
      isDefault: false,
      isImageLocked: false,
      // No targetAudience → visible to everyone
    ),
    _GroupItem(
      id: 'disc_postnatal_fitness',
      name: 'Postnatal Fitness',
      description:
          'Safely rebuild your strength and fitness after pregnancy with expert advice and community support.',
      imageUrl:
          'https://images.pexels.com/photos/3094222/pexels-photo-3094222.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 967,
      category: 'FITNESS',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
    ),
    _GroupItem(
      id: 'disc_working_parents',
      name: 'Working Parents Network',
      description:
          'Balancing work and family life. Share tips on flexible working, childcare and career progression.',
      imageUrl:
          'https://images.pexels.com/photos/6957653/pexels-photo-6957653.jpeg?auto=compress&cs=tinysrgb&w=600',
      memberCount: 743,
      category: 'WORK-LIFE',
      isDefault: false,
      isImageLocked: false,
      // No targetAudience → visible to everyone
    ),
  ];

  List<_GroupItem> get _filteredGroups {
    // 1. Private groups are never shown on the Discover tab
    // 2. Groups with targetAudience are only shown if user matches ALL criteria
    // 3. User-created public groups: filter by same borough
    List<_GroupItem> results = _allDiscoverGroups.where((g) {
      if (g.isPrivate) return false;
      if (!g.isVisibleTo(_userParentType, _userStagesOfLife)) return false;
      // Borough matching for user-created groups
      if (g.creatorBorough != null && g.creatorBorough!.isNotEmpty && _userBorough != null) {
        if (g.creatorBorough != _userBorough && g.creatorBorough != 'Unknown Borough') {
          return false;
        }
      }
      return true;
    }).toList();
    // Apply category filter
    if (_selectedFilter != 'All') {
      final f = _selectedFilter.toLowerCase();
      results = results
          .where((g) =>
              g.category.toLowerCase().contains(f) ||
              g.name.toLowerCase().contains(f))
          .toList();
    }
    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      results = results
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              g.category.toLowerCase().contains(q) ||
              g.description.toLowerCase().contains(q))
          .toList();
    }
    // Apply sort
    switch (_selectedSort) {
      case 'Most Members':
        results.sort((a, b) => b.memberCount.compareTo(a.memberCount));
        break;
      case 'Newest':
        results = results.reversed.toList();
        break;
      case 'A-Z':
        results.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      default: // 'Recommended' — default order
        break;
    }
    return results;
  }

  Future<void> _onJoinTap(String groupId) async {
    final isAlreadyJoined = _invitationService.isGroupJoined(groupId);
    if (isAlreadyJoined) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already joined this group'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final group = _allDiscoverGroups.firstWhere((g) => g.id == groupId);

    // Get user name
    final userName = _onboardingService.name ?? 'You';

    // Create a Group object from _GroupItem for persistence
    final groupObj = Group(
      id: group.id,
      name: group.name,
      description: group.description,
      imageUrl: group.imageUrl,
      memberCount: group.memberCount + 1,
      category: group.category,
      isJoined: true,
      isPrivate: false,
      targetAudience: group.targetAudience,
      creatorBorough: group.creatorBorough,
      creatorId: group.creatorId,
      creatorName: group.creatorName,
    );

    await _invitationService.joinPublicGroup(groupObj, userName);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined ${group.name}! Check your Messages tab.'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── Filter & Sort bottom sheet ─────────────────────────────────────────
  void _showFilterSortSheet() {
    String tempFilter = _selectedFilter;
    String tempSort = _selectedSort;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: HuddlColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter & Sort',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            tempFilter = 'All';
                            tempSort = 'Recommended';
                          });
                        },
                        child: Text(
                          'Reset',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Category',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _filterLabels.map((label) {
                      final isActive = tempFilter == label;
                      return GestureDetector(
                        onTap: () =>
                            setSheetState(() => tempFilter = label),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: isActive
                                ? HuddlColors.primary
                                : HuddlColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? HuddlColors.primary
                                  : HuddlColors.divider,
                            ),
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? HuddlColors.white
                                  : HuddlColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sort by',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...(_sortOptions.map((option) {
                    final isActive = tempSort == option;
                    return GestureDetector(
                      onTap: () =>
                          setSheetState(() => tempSort = option),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? HuddlColors.peachLight
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? HuddlColors.primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _sortIcon(option),
                              size: 18,
                              color: isActive
                                  ? HuddlColors.primary
                                  : HuddlColors.textHint,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              option,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isActive
                                    ? HuddlColors.primary
                                    : HuddlColors.textDark,
                              ),
                            ),
                            const Spacer(),
                            if (isActive)
                              const Icon(Icons.check_circle,
                                  size: 20, color: HuddlColors.primary),
                          ],
                        ),
                      ),
                    );
                  })),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedFilter = tempFilter;
                          _selectedSort = tempSort;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: Text(
                        'Apply',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _sortIcon(String option) {
    switch (option) {
      case 'Most Members':
        return Icons.group;
      case 'Newest':
        return Icons.schedule;
      case 'A-Z':
        return Icons.sort_by_alpha;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _filteredGroups;

    final bool hasActiveFilters =
        _selectedFilter != 'All' || _selectedSort != 'Recommended';

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── Search bar / Filter-sort bar ─────────────────────────
            SliverToBoxAdapter(
              child: Container(
                color: HuddlColors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: _showSearchField
                    ? Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: HuddlColors.background,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: HuddlColors.textDark),
                                decoration: InputDecoration(
                                  hintText: 'Search groups...',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: HuddlColors.textHint),
                                  prefixIcon: const Icon(Icons.search,
                                      size: 20, color: HuddlColors.textHint),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? GestureDetector(
                                          onTap: () => setState(() {
                                            _searchController.clear();
                                            _searchQuery = '';
                                          }),
                                          child: const Icon(Icons.close,
                                              size: 18,
                                              color: HuddlColors.textHint),
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 11),
                                ),
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() {
                              _showSearchField = false;
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text('Cancel',
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: HuddlColors.primary,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      )
                    : GestureDetector(
                        onTap: _showFilterSortSheet,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: HuddlColors.background,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.tune,
                                  size: 18,
                                  color: hasActiveFilters
                                      ? HuddlColors.primary
                                      : HuddlColors.textHint),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasActiveFilters
                                      ? 'Filtered: $_selectedFilter \u00B7 $_selectedSort'
                                      : 'Filter and sort!',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: hasActiveFilters
                                        ? HuddlColors.textDark
                                        : HuddlColors.textHint,
                                    fontWeight: hasActiveFilters
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _showSearchField = true),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.search,
                                      size: 22,
                                      color: HuddlColors.textDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),

            // ── CTA Card — right under search bar ─────────────────────
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () async {
                  final result = await Navigator.pushNamed(context, '/create_group');
                  if (result != null) {
                    widget.groupsChangedNotifier.value++;
                  }
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: HuddlColors.peachLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Positioned(
                              left: 0, top: 4,
                              child: Container(
                                width: 10, height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFFD54F),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0, bottom: 6,
                              child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF90CAF9),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const Icon(Icons.diversity_3,
                                size: 30, color: HuddlColors.primary),
                            Positioned(
                              right: 4, top: 4,
                              child: Container(
                                width: 20, height: 20,
                                decoration: BoxDecoration(
                                  color: HuddlColors.teal,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: HuddlColors.white, width: 2),
                                ),
                                child: const Icon(Icons.add,
                                    size: 11, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Haven\'t found the perfect group?',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textDark,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Don\'t worry, add your own!',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: HuddlColors.textHint,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final result = await Navigator.pushNamed(context, '/create_group');
                                  if (result != null) {
                                    widget.groupsChangedNotifier.value++;
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: HuddlColors.primary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  'Create New Group',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── "Suggested for you" header ───────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested for you',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userBorough != null && _userBorough != 'Unknown Borough'
                          ? 'Groups in $_userBorough and beyond'
                          : 'Groups you might be interested in',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Group cards ──────────────────────────────────────────
            if (groups.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final group = groups[index];
                    final isJoined = _invitationService.isGroupJoined(group.id) ||
                        group.creatorId == 'current_user';
                    return _DiscoverGroupCard(
                      group: group,
                      isJoined: isJoined,
                      onJoinTap: () => _onJoinTap(group.id),
                      onTap: () {
                        Navigator.pushNamed(context, '/group_details',
                            arguments: {
                              'groupId': group.id,
                              'groupName': group.name,
                              'groupImageUrl': group.imageUrl,
                              'groupDescription': group.description,
                              'memberCount': group.memberCount,
                              'isPrivate': group.isPrivate,
                              'creatorId': group.creatorId,
                              'isJoined': isJoined,
                            });
                      },
                    );
                  },
                  childCount: groups.length,
                ),
              ),

            // ── Empty state ──────────────────────────────────────────
            if (groups.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off,
                          size: 48, color: HuddlColors.textHint),
                      const SizedBox(height: 12),
                      Text('No groups match your search',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark)),
                      const SizedBox(height: 8),
                      Text('Try adjusting your filters or search terms.',
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: HuddlColors.textHint),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // ── FAB ──────────────────────────────────────────────────────
        Positioned(
          bottom: 24,
          right: 16,
          child: Material(
            elevation: 6,
            shadowColor: HuddlColors.primary.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            color: HuddlColors.primary,
            child: InkWell(
              onTap: () async {
                final result = await Navigator.pushNamed(context, '/create_group');
                if (result != null) {
                  widget.groupsChangedNotifier.value++;
                }
              },
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.add, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DISCOVER GROUP CARD
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, Map<String, dynamic>> _discoverCardStyles = {
  'disc_first_time_mums': {'icon': Icons.child_friendly, 'color': Color(0xFFFF975C)},
  'disc_dads_connect': {'icon': Icons.man, 'color': Color(0xFF3580F0)},
  'disc_baby_sleep': {'icon': Icons.bedtime, 'color': Color(0xFFA16AE9)},
  'disc_healthy_meals': {'icon': Icons.restaurant, 'color': Color(0xFF199A85)},
  'disc_postnatal_fitness': {'icon': Icons.fitness_center, 'color': Color(0xFFFF7575)},
  'disc_working_parents': {'icon': Icons.work_outline, 'color': Color(0xFF5B9DFF)},
};

class _DiscoverGroupCard extends StatelessWidget {
  final _GroupItem group;
  final bool isJoined;
  final VoidCallback onJoinTap;
  final VoidCallback onTap;

  const _DiscoverGroupCard({
    required this.group,
    required this.isJoined,
    required this.onJoinTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _discoverCardStyles[group.id] ??
        {'icon': Icons.people, 'color': HuddlColors.primary};
    final Color iconColor = style['color'] as Color;
    final IconData iconData = style['icon'] as IconData;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Icon thumbnail or group image ─────────────────────
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildGroupImage(iconData, iconColor),
            ),
            const SizedBox(width: 12),
            // ── Name + member count ──────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (group.creatorId == 'current_user') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Your group',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.teal,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.description.isNotEmpty
                        ? group.description
                        : '${group.memberCount} members',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (group.description.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      '${group.memberCount} members${group.creatorBorough != null && group.creatorBorough!.isNotEmpty && group.creatorBorough != 'Unknown Borough' ? ' \u00B7 ${group.creatorBorough}' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.textHint.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── Join / Joined button ─────────────────────────────
            GestureDetector(
              onTap: isJoined ? null : onJoinTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isJoined ? HuddlColors.background : null,
                  gradient: isJoined ? null : HuddlColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: isJoined
                      ? Border.all(color: HuddlColors.divider)
                      : null,
                ),
                child: Text(
                  isJoined ? 'Joined' : 'Join',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color:
                        isJoined ? HuddlColors.textSecondary : HuddlColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the group thumbnail from any source: asset path, http URL,
  /// or base64 data-URI. Falls back to the category icon when the image
  /// is empty or fails to load.
  Widget _buildGroupImage(IconData fallbackIcon, Color fallbackColor) {
    final url = group.imageUrl;
    if (url.isEmpty) {
      return Icon(fallbackIcon, color: fallbackColor, size: 28);
    }

    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        width: 56,
        height: 56,
        errorBuilder: (_, __, ___) =>
            Icon(fallbackIcon, color: fallbackColor, size: 28),
      );
    }

    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: 56,
        height: 56,
        errorBuilder: (_, __, ___) =>
            Icon(fallbackIcon, color: fallbackColor, size: 28),
      );
    }

    if (url.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(url);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: 56,
            height: 56,
            errorBuilder: (_, __, ___) =>
                Icon(fallbackIcon, color: fallbackColor, size: 28),
          );
        }
      } catch (_) {
        // fall through
      }
    }

    return Icon(fallbackIcon, color: fallbackColor, size: 28);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAVED TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedTab extends StatefulWidget {
  @override
  State<_SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<_SavedTab> {
  final SavedMessageService _savedMessageService = SavedMessageService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
    _savedMessageService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _savedMessageService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _savedMessageService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: HuddlColors.primary),
      );
    }

    final saved = _savedMessageService.savedMessages;

    if (saved.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: HuddlColors.peachLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bookmark_border,
                size: 40,
                color: HuddlColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved messages yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Long-press a message in any group or DM\nto save it here for later.',
              style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: saved.length,
      itemBuilder: (context, index) {
        final msg = saved[index];
        return _SavedMessageCard(
          savedMessage: msg,
          onTap: () => _navigateToSource(msg),
          onDelete: () async {
            await _savedMessageService.unsaveMessage(msg.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Message removed from saved'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          },
        );
      },
    );
  }

  void _navigateToSource(SavedMessage msg) {
    if (msg.isFromGroup) {
      Navigator.pushNamed(context, '/group_chat', arguments: {
        'groupId': msg.groupId ?? '',
        'groupName': msg.groupName ?? 'Group',
        'groupImageUrl': msg.groupImageUrl ?? '',
      });
    } else {
      Navigator.pushNamed(context, '/dm_chat', arguments: {
        'recipientId': msg.dmRecipientId ?? '',
        'recipientName': msg.dmRecipientName ?? 'Chat',
        'recipientAvatarColor': msg.dmRecipientAvatarColor ?? '#FF975C',
        'conversationId': msg.dmConversationId,
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAVED MESSAGE CARD — shows message, source, timestamp, and tap-to-navigate
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedMessageCard extends StatelessWidget {
  final SavedMessage savedMessage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedMessageCard({
    required this.savedMessage,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isGroup = savedMessage.isFromGroup;

    return Dismissible(
      key: Key(savedMessage.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.1),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Source info row
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isGroup
                          ? HuddlColors.peachLight
                          : _savedColorFromHex(
                                  savedMessage.dmRecipientAvatarColor ?? '#FF975C')
                              .withValues(alpha: 0.15),
                      borderRadius: isGroup
                          ? BorderRadius.circular(8)
                          : BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: isGroup
                          ? const Icon(Icons.people, size: 14, color: HuddlColors.primary)
                          : Text(
                              (savedMessage.dmRecipientName ?? '?')[0].toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _savedColorFromHex(
                                    savedMessage.dmRecipientAvatarColor ?? '#FF975C'),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isGroup ? Icons.group : Icons.person,
                              size: 12,
                              color: HuddlColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'From ${savedMessage.sourceName}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatSavedTime(savedMessage.savedAt),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Message content
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: HuddlColors.divider.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          savedMessage.senderName,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatMessageTime(savedMessage.timestamp),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: HuddlColors.textHint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      savedMessage.message,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.textDark,
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Tap hint
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.open_in_new, size: 12, color: HuddlColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to go to ${isGroup ? 'group' : 'conversation'}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
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

  String _formatSavedTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}';
  }

  String _formatMessageTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

Color _savedColorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWIPE ACTION ROW — swipe left for Delete (red), right for Mark read/unread (teal)
// ═══════════════════════════════════════════════════════════════════════════════

class _SwipeActionRow extends StatefulWidget {
  final Widget child;
  final bool isUnread;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;

  const _SwipeActionRow({
    super.key,
    required this.child,
    required this.isUnread,
    required this.onDelete,
    required this.onToggleRead,
  });

  @override
  State<_SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<_SwipeActionRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _dragExtent = 0;
  static const double _actionThreshold = 80;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapBack() {
    _controller.addListener(_animateBack);
    _controller.forward(from: 0);
  }

  void _animateBack() {
    setState(() {
      _dragExtent = _dragExtent * (1 - _controller.value);
    });
    if (_controller.isCompleted) {
      _controller.removeListener(_animateBack);
      _controller.reset();
      setState(() => _dragExtent = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double clampedDrag = _dragExtent.clamp(-_actionThreshold, _actionThreshold);
    final bool showDelete = clampedDrag < -20;
    final bool showRead = clampedDrag > 20;

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragExtent += details.delta.dx;
          _dragExtent = _dragExtent.clamp(-_actionThreshold - 20, _actionThreshold + 20);
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragExtent < -_actionThreshold * 0.6) {
          // Swiped left enough — trigger delete
          _snapBack();
          widget.onDelete();
        } else if (_dragExtent > _actionThreshold * 0.6) {
          // Swiped right enough — toggle read
          _snapBack();
          widget.onToggleRead();
        } else {
          _snapBack();
        }
      },
      child: Stack(
        children: [
          // Background action indicators
          Positioned.fill(
            child: Row(
              children: [
                // Left side — teal mark read/unread (revealed on right swipe)
                Expanded(
                  child: Container(
                    color: const Color(0xFF34C7A0),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 24),
                    child: AnimatedOpacity(
                      opacity: showRead ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isUnread
                                ? Icons.mark_chat_read
                                : Icons.mark_chat_unread,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isUnread ? 'Read' : 'Unread',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Right side — red delete (revealed on left swipe)
                Expanded(
                  child: Container(
                    color: const Color(0xFFFF4D4D),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: AnimatedOpacity(
                      opacity: showDelete ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delete, color: Colors.white, size: 22),
                          const SizedBox(height: 2),
                          Text(
                            'Delete',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Foreground — actual row content, shifted horizontally
          Transform.translate(
            offset: Offset(clampedDrag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? HuddlColors.textDark),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? HuddlColors.textDark,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  final VoidCallback onSearch;
  const _EmptyMessagesState({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: HuddlColors.peachLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: HuddlColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Join a group to start chatting\nwith your community.',
              style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODEL — _GroupItem (internal to this screen, extends Group logic)
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupItem {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int memberCount;
  final String category;
  final bool isDefault;
  final bool isImageLocked;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastMessageTime;
  final int? unreadCount;
  final bool isPrivate;
  final List<String> targetAudience;
  final String? creatorId;
  final String? creatorName;
  final String? creatorBorough;

  _GroupItem({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.memberCount,
    required this.category,
    required this.isDefault,
    required this.isImageLocked,
    this.lastMessage,
    this.lastSenderName,
    this.lastMessageTime,
    this.unreadCount,
    this.isPrivate = false,
    this.targetAudience = const [],
    this.creatorId,
    this.creatorName,
    this.creatorBorough,
  });

  factory _GroupItem.fromGroup(Group g, {required bool isDefault}) {
    return _GroupItem(
      id: g.id,
      name: g.name,
      description: g.description,
      imageUrl: g.imageUrl,
      memberCount: g.memberCount,
      category: g.category,
      isDefault: isDefault,
      isImageLocked: g.isImageLocked,
      lastMessage: g.lastMessage,
      lastSenderName: g.lastSenderName,
      lastMessageTime: g.lastMessageTime,
      unreadCount: g.unreadCount,
      isPrivate: g.isPrivate,
      targetAudience: g.targetAudience,
      creatorId: g.creatorId,
      creatorName: g.creatorName,
      creatorBorough: g.creatorBorough,
    );
  }

  bool isVisibleTo(String? parentType, List<String> stagesOfLife) {
    if (targetAudience.isEmpty) return true;
    for (final label in targetAudience) {
      switch (label) {
        case 'Mums':
          if (parentType != 'mum') return false;
          break;
        case 'Dads':
          if (parentType != 'dad') return false;
          break;
        case 'Parents expecting a baby':
          if (!stagesOfLife.contains('expecting')) return false;
          break;
        case 'Aspiring parents':
          if (!stagesOfLife.contains('aspiring')) return false;
          break;
      }
    }
    return true;
  }

  _GroupItem copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    int? memberCount,
    String? category,
    bool? isDefault,
    bool? isImageLocked,
    String? lastMessage,
    String? lastSenderName,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isPrivate,
    List<String>? targetAudience,
    String? creatorId,
    String? creatorName,
    String? creatorBorough,
  }) {
    return _GroupItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      memberCount: memberCount ?? this.memberCount,
      category: category ?? this.category,
      isDefault: isDefault ?? this.isDefault,
      isImageLocked: isImageLocked ?? this.isImageLocked,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isPrivate: isPrivate ?? this.isPrivate,
      targetAudience: targetAudience ?? this.targetAudience,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorBorough: creatorBorough ?? this.creatorBorough,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'memberCount': memberCount,
        'category': category,
        'isDefault': isDefault,
        'isImageLocked': isImageLocked,
        'lastMessage': lastMessage,
        'lastSenderName': lastSenderName,
        'lastMessageTime': lastMessageTime?.toIso8601String(),
        'unreadCount': unreadCount,
        'isPrivate': isPrivate,
        'targetAudience': targetAudience,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'creatorBorough': creatorBorough,
      };
}
