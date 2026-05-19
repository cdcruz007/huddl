import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../services/realtime_dm_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/event_service.dart';
import '../../services/saved_message_service.dart';
import '../../services/message_search_service.dart';
import '../../models/saved_message.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/subscription_service.dart';
import '../../services/ai_chat_summariser_service.dart';
import '../../services/messages_ai_service.dart';
import '../../widgets/upgrade_prompt.dart';
import '../../services/discover_ai_service.dart';
import '../events/events_screen.dart' show ImGoingTab;
import '../../widgets/borough_badge.dart';
import '../../services/borough_scope_guard.dart';
import '../../utils/borough_ui_helpers.dart';
import '../../widgets/common/huddl_empty_state.dart';
import '../../services/firestore_service.dart';
import 'group_chat_screen.dart' show GroupChatScreen;

// ── Design tokens — aliases to the single source of truth (HuddlColors) ─────
const Color _kOnline = HuddlColors.teal; // HuddlColors.teal — online = positive status

// ── Member avatar photo pool — used for overlapping circles in group cards ──
// Deterministic selection: (group.id.hashCode + i) % length
const List<String> _kMemberAvatars = [
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=100&h=100&fit=crop&crop=face',
];

// ── Persistence key for user-created groups ──────────────────────────────
const String _userGroupsKey = 'user_created_groups_v1';
// ── Persistence key for groups the user has explicitly left ─────────────
const String _leftGroupsKey = 'left_groups_v1';

/// Platform-adaptive font family: SF Pro on iOS, Poppins elsewhere (P2).
TextStyle _adaptiveText({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color? color,
  double? height,
  FontStyle? fontStyle,
  double? letterSpacing,
}) {
  final bool isApple = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);
  if (isApple) {
    return TextStyle(
      fontFamily: '.SF Pro Text',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
    );
  }
  return GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
  );
}

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

  /// Shared search query — passed to each tab so they can filter their content.
  final ValueNotifier<String> _searchNotifier = ValueNotifier<String>('');
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchActive = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _clearSearch();       // reset search when switching tabs
        setState(() {});      // rebuild hint text + header icons
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _searchNotifier.value = '';
    setState(() => _isSearchActive = false);
  }

  String get _searchHint {
    switch (_tabController.index) {
      case 0:  return 'Search chats…';
      case 1:  return 'Search attending…';
      case 2:  return 'Search saved…';
      default: return 'Search…';
    }
  }

  @override
  void dispose() {
    _groupsChangedNotifier.dispose();
    _searchNotifier.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header: Connect title (or search bar) + tabs ──────────
            Container(
              color: context.hc.surface,
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row — collapses into search bar when active
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _isSearchActive
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: Row(
                      children: [
                        Text(
                          'Connect',
                          style: _adaptiveText(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const BoroughScopeChip(feature: HuddlFeature.chat),
                        const Spacer(),
                        // 🔍 Search trigger icon — top-right, above tabs
                        IconButton(
                          onPressed: () {
                            setState(() => _isSearchActive = true);
                            Future.microtask(() => _searchFocusNode.requestFocus());
                          },
                          icon: Icon(
                            Icons.search,
                            color: context.hc.textSecondary,
                            size: 22,
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: 'Search',
                        ),
                      ],
                    ),
                    // Expanded search bar — replaces title row
                    secondChild: SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                color: context.hc.inputBg,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  Icon(Icons.search,
                                      size: 16,
                                      color: context.hc.textTertiary
                                          .withValues(alpha: 0.7)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      autofocus: false,
                                      onChanged: (val) =>
                                          _searchNotifier.value = val,
                                      style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: context.hc.textPrimary),
                                      decoration: InputDecoration(
                                        hintText: _searchHint,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                        hintStyle: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: context.hc.textTertiary),
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        _searchNotifier.value = '';
                                        setState(() {});
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Icon(Icons.close,
                                            size: 15,
                                            color: context.hc.textTertiary),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _clearSearch,
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tabs — always visible, no search bar below them
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Messages'),
                      Tab(text: 'Attending'),
                      Tab(text: 'Saved'),
                    ],
                    labelColor: HuddlColors.primary,
                    unselectedLabelColor: HuddlColors.textHint,
                    labelStyle: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w400),
                    indicatorColor: HuddlColors.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: HuddlColors.divider,
                    padding: EdgeInsets.zero,
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ],
              ),
            ),
            // ── Tab content ──────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MessagesTab(
                    groupsChangedNotifier: _groupsChangedNotifier,
                    searchNotifier: _searchNotifier,
                  ),
                  ImGoingTab(searchNotifier: _searchNotifier),
                  _SavedTab(searchNotifier: _searchNotifier),
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
  final ValueNotifier<String> searchNotifier;
  const _MessagesTab({
    required this.groupsChangedNotifier,
    required this.searchNotifier,
  });

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  final DefaultGroupService _groupService = DefaultGroupService();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final InvitationService _invitationService = InvitationService();
  final DMService _dmService = DMService();
  final RealtimeDMService _realtimeDMService = RealtimeDMService();
  final AiChatSummariserService _summariser = AiChatSummariserService();
  final MessagesAiService _aiService = MessagesAiService();

  List<_GroupItem> _allGroups = [];
  List<_GroupItem> _filteredGroups = [];
  List<GroupInvitation> _pendingInvitations = [];
  List<DMConversation> _dmConversations = [];
  List<DMConversation> _filteredDMs = [];
  StreamSubscription<List<RealtimeDMConversation>>? _firestoreConvSub;
  StreamSubscription<void>? _firestoreGroupsSub;   // watches groups for remote last-message updates
  final Set<String> _pinnedGroupIds = {};
  final Set<String> _mutedGroupIds = {};
  bool _isLoading = true;
  bool _hasLoadError = false;
  String _errorMessage = '';
  String _searchQuery = '';
  bool _summariesLoaded = false;
  bool _showAiSuggestions = false;

  // ── Deep search state ─────────────────────────────────────────────────
  List<MessageSearchResult> _deepSearchResults = [];
  bool _isDeepSearching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _aiService.initialize();
    // Defer ALL listener registration AND data loading to after the first
    // frame. Any ChangeNotifier that fires notifyListeners() before or during
    // the first build will otherwise trigger setState-during-build on MainShell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dmService.addListener(_onDMUpdate);
      _invitationService.addListener(_onGroupsChanged);
      widget.groupsChangedNotifier.addListener(_onGroupsChanged);
      // Listen for event "Count Me In" group chat creation
      EventService.groupChatCreated.addListener(_onGroupsChanged);
      // Re-sort list whenever the user sends a message in any group chat
      GroupChatScreen.messageSent.addListener(_onMessageSentFromChat);
      // Listen to the shared search notifier from GroupsScreen
      widget.searchNotifier.addListener(_onSearchChanged);
      _loadGroups();
      _loadMutedAndPinned();
      _loadDemoSummaries();
      _subscribeToFirestoreGroups();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _firestoreConvSub?.cancel();
    _firestoreGroupsSub?.cancel();
    EventService.groupChatCreated.removeListener(_onGroupsChanged);
    widget.groupsChangedNotifier.removeListener(_onGroupsChanged);
    _invitationService.removeListener(_onGroupsChanged);
    GroupChatScreen.messageSent.removeListener(_onMessageSentFromChat);
    widget.searchNotifier.removeListener(_onSearchChanged);
    _dmService.removeListener(_onDMUpdate);
    super.dispose();
  }

  void _onGroupsChanged() {
    _loadGroups();
  }

  /// Called whenever the shared search notifier changes value.
  void _onSearchChanged() {
    setState(() {
      _searchQuery = widget.searchNotifier.value;
      _applyFilter();
    });
  }

  /// Subscribe to Firestore groups collection for the current user.
  /// When another user sends a message the group doc's lastMessage /
  /// lastMessageTime fields are updated — this stream picks that up and
  /// re-sorts the list without a full reload.
  void _subscribeToFirestoreGroups() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _firestoreGroupsSub?.cancel();
    _firestoreGroupsSub = FirestoreService()
        .myGroupsStream(uid)
        .listen((updatedGroups) {
      if (!mounted) return;
      bool changed = false;

      for (final updated in updatedGroups) {
        final idx = _allGroups.indexWhere((g) => g.id == updated.id);

        if (idx < 0) {
          // ── New group appeared in Firestore that isn't in the local list yet
          // (e.g. the user was added to a group on another device, or the
          // initial load completed before the Firestore snapshot arrived).
          // Add it so the list stays complete and correctly sorted.
          final leftGroupIds = _allGroups
              .where((g) => g.id.isEmpty) // placeholder to avoid async here
              .map((g) => g.id)
              .toSet();
          if (!leftGroupIds.contains(updated.id)) {
            _allGroups.add(_GroupItem.fromGroup(updated, isDefault: true));
            changed = true;
          }
        } else {
          final existing = _allGroups[idx];
          // Only update if Firestore has a NEWER timestamp than local cache
          final firestoreTime = updated.lastMessageTime;
          final localTime     = existing.lastMessageTime;
          if (firestoreTime != null &&
              (localTime == null || firestoreTime.isAfter(localTime))) {
            _allGroups[idx] = existing.copyWith(
              lastMessage:     updated.lastMessage,
              lastSenderName:  updated.lastSenderName,
              lastMessageTime: firestoreTime,
            );
            changed = true;
          }
        }
      }

      if (changed) {
        setState(() => _applyFilter());
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint('[groups_screen] Firestore groups stream error: $e');
    });
  }

  /// Called whenever the user sends a message in any GroupChatScreen.
  /// Refreshes last-message data so the list re-sorts immediately.
  void _onMessageSentFromChat() {
    final payload = GroupChatScreen.messageSent.value;
    final sentGroupId = payload['groupId'] as String?;
    if (sentGroupId == null) return;
    _refreshLastMessageForGroup(sentGroupId);
  }

  /// Reads the latest message from storage for [groupId] and updates
  /// the corresponding [_GroupItem] so the list re-sorts correctly.
  Future<void> _refreshLastMessageForGroup(String groupId) async {
    try {
      DateTime? latestTime;
      String? latestText;
      String? latestSender;

      // ── 1. User-typed text messages ───────────────────────────────
      final textKey = 'gc_user_texts_$groupId';
      final textRaw = await BrowserStorage.getString(textKey);
      if (textRaw != null) {
        final msgs = (json.decode(textRaw) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final m in msgs) {
          final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
          if (ts != null && (latestTime == null || ts.isAfter(latestTime))) {
            latestTime = ts;
            latestText = m['message'] as String?;
            latestSender = 'You';
          }
        }
      }

      // ── 2. Forwarded / card messages ─────────────────────────────
      final fwdKey = 'group_messages_$groupId';
      final fwdRaw = await BrowserStorage.getString(fwdKey);
      if (fwdRaw != null) {
        final msgs = (json.decode(fwdRaw) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final m in msgs) {
          final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
          if (ts != null && (latestTime == null || ts.isAfter(latestTime))) {
            latestTime = ts;
            final isMe = (m['senderId'] as String? ?? '') == 'current_user';
            latestSender = isMe ? 'You' : (m['senderName'] as String? ?? '');
            // Show a friendly label for card types
            if (m['isMeetupCard'] == true) {
              latestText = '📅 Shared a meetup';
            } else if (m['isGroupCard'] == true) {
              latestText = '👥 Shared a group';
            } else if (m['isEventCard'] == true) {
              latestText = '📌 Shared an event';
            } else if (m['isItemCard'] == true) {
              latestText = '🛍 Shared a listing';
            } else {
              latestText = m['message'] as String?;
            }
          }
        }
      }

      // ── 3. Media messages (images, documents, location pins) ──────
      final mediaRaw =
          await BrowserStorage.getString('gc_user_media_$groupId');
      if (mediaRaw != null) {
        final decoded = json.decode(mediaRaw) as Map<String, dynamic>;
        final imgs = (decoded['images'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        final docs = (decoded['documents'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        for (final m in [...imgs, ...docs]) {
          final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
          if (ts != null && (latestTime == null || ts.isAfter(latestTime))) {
            latestTime = ts;
            latestSender = 'You';
            if (m['isLocationPin'] == true) {
              latestText = '📍 Shared a location';
            } else if (m.containsKey('fileName')) {
              latestText = '📄 ${m['fileName']}';
            } else {
              latestText = '📷 Photo';
            }
          }
        }
      }

      if (latestTime == null || !mounted) return;

      final finalText = latestText;
      final finalSender = latestSender;
      final finalTime = latestTime;

      setState(() {
        final idx = _allGroups.indexWhere((g) => g.id == groupId);
        if (idx >= 0 &&
            (finalTime.isAfter(
                _allGroups[idx].lastMessageTime ?? DateTime(2000)))) {
          _allGroups[idx] = _allGroups[idx].copyWith(
            lastMessage: finalSender != null && finalText != null
                ? '$finalSender: $finalText'
                : finalText,
            lastSenderName: finalSender,
            lastMessageTime: finalTime,
          );
          _applyFilter(); // re-sort
        }
      });
    } catch (_) {}
  }

  Future<void> _loadDemoSummaries() async {
    await _summariser.generateDemoSummaries();
    if (mounted) setState(() => _summariesLoaded = true);
  }

  // ── Muted & Pinned persistence ────────────────────────────────────
  static const String _mutedKey = 'huddl_muted_ids';
  static const String _pinnedKey = 'huddl_pinned_ids';

  Future<void> _loadMutedAndPinned() async {
    final mutedStored = await BrowserStorage.getString(_mutedKey);
    if (mutedStored != null && mutedStored.isNotEmpty) {
      final List<dynamic> decoded = json.decode(mutedStored);
      if (mounted) {
        setState(() {
          _mutedGroupIds.addAll(decoded.cast<String>());
        });
      }
    }
    final pinnedStored = await BrowserStorage.getString(_pinnedKey);
    if (pinnedStored != null && pinnedStored.isNotEmpty) {
      final List<dynamic> decoded = json.decode(pinnedStored);
      if (mounted) {
        setState(() {
          _pinnedGroupIds.addAll(decoded.cast<String>());
        });
      }
    }
  }

  Future<void> _saveMutedAndPinned() async {
    await BrowserStorage.setString(
        _mutedKey, json.encode(_mutedGroupIds.toList()));
    await BrowserStorage.setString(
        _pinnedKey, json.encode(_pinnedGroupIds.toList()));
  }



  void _onDMUpdate() {
    if (mounted) {
      setState(() {
        // Preserve Firestore conversations; only refresh local demo ones
        final firestoreConvs = _dmConversations.where((c) => c.id.startsWith('conv_')).toList();
        _dmConversations = List.from(_dmService.conversations)..addAll(firestoreConvs);
        _applyFilter();
      });
    }
  }

  String _avatarColorForUid(String uid) {
    const colors = [
      '#FF975C', '#3580F0', '#199A85', '#A16AE9',
      '#5B9DFF', '#E8A838', '#FF7575', '#34C759',
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      // Ensure all services have loaded their persisted data
      await _onboardingService.initialize();
      await _groupService.initialize();
      await _invitationService.initialize();
      await _dmService.initialize();

      // Load DM conversations (local demo + real Firestore)
      _dmConversations = List.from(_dmService.conversations);

      // Subscribe to real Firestore conversations (real user DMs)
      if (FirebaseAuth.instance.currentUser != null) {
        _firestoreConvSub?.cancel();
        _firestoreConvSub = _realtimeDMService.conversationsStream().listen(
          (firestoreConvs) {
            if (!mounted) return;
            // Convert RealtimeDMConversation → DMConversation
            final converted = firestoreConvs.map((fc) => DMConversation(
              id: fc.id,
              recipientId: fc.otherUserId,
              recipientName: fc.otherUserName,
              recipientAvatarColor: _avatarColorForUid(fc.otherUserId),
              recipientPhotoUrl: fc.otherUserPhotoUrl.isNotEmpty ? fc.otherUserPhotoUrl : null,
              lastMessage: fc.lastMessage,
              lastSenderName: fc.lastSenderName,
              lastMessageTime: fc.lastMessageAt,
              unreadCount: fc.unreadCount,
              isOnline: false,
            )).toList();

            setState(() {
              // Remove any existing Firestore-backed convs and replace
              _dmConversations.removeWhere((c) => c.id.startsWith('conv_'));
              _dmConversations.addAll(converted);
              _applyFilter();
            });
          },
          onError: (e) {
            if (kDebugMode) debugPrint('[groups_screen] Firestore conv stream error: $e');
          },
        );
      }

      // Use the real Firebase UID (fallback to onboarding name hash so
      // the key is still unique per device even before login completes).
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      final userId = firebaseUid ?? 'user_${_onboardingService.name?.hashCode ?? 0}';

      // ── Load groups the user has explicitly left (never re-join these) ──
      final leftGroupIds = await _getLeftGroupIds();

      // ── 1. Try to get previously assigned default groups ──────────
      List<Group> defaultGroups =
          await _groupService.getUserGroups(userId);
      // Filter out any groups the user has explicitly left
      defaultGroups = defaultGroups.where((g) => !leftGroupIds.contains(g.id)).toList();

      // ── 2. If none, try to assign now based on onboarding data ──
      //    But only assign groups the user hasn't explicitly left
      if (defaultGroups.isEmpty) {
        final assigned = await _groupService.assignUserToDefaultGroups(userId);
        defaultGroups = assigned.where((g) => !leftGroupIds.contains(g.id)).toList();
        // Remove any re-assigned left groups from the service membership
        for (final leftId in leftGroupIds) {
          await _groupService.leaveGroup(userId, leftId);
        }
      }

      // ── 3. Last resort: re-join existing defaults ─────────────────
      //    Only join groups the user has NOT explicitly left
      if (defaultGroups.isEmpty) {
        final allDefaults = _groupService.getAllDefaultGroups()
            .where((g) => !leftGroupIds.contains(g.id))
            .toList();
        if (allDefaults.isNotEmpty) {
          for (final g in allDefaults) {
            _groupService.joinGroup(userId, g.id);
          }
          defaultGroups = (await _groupService.getUserGroups(userId))
              .where((g) => !leftGroupIds.contains(g.id))
              .toList();
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

      // ── Load groups from Firestore (cross-device, real memberIds) ────
      // This ensures users see shared groups regardless of which device
      // assigned them locally. Groups stored in Firestore with the user's
      // Firebase UID in memberIds are always shown.
      List<Group> firestoreGroups = [];
      try {
        firestoreGroups = await FirestoreService().getMyGroups()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('[groups_screen] Firestore groups load error: $e');
      }

      // ── Merge into _GroupItem list ─────────────────────────────
      final List<_GroupItem> items = [];

      // Firestore groups take priority — they're the source of truth
      for (final g in firestoreGroups) {
        if (!leftGroupIds.contains(g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: true));
        }
      }

      // Local default groups (device-only) that aren't already in Firestore
      for (final g in defaultGroups) {
        if (!items.any((i) => i.id == g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: true));
        }
      }
      for (final g in userGroups) {
        if (!items.any((i) => i.id == g.id) && !leftGroupIds.contains(g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: false));
        }
      }

      // ── Joined public groups (from Discover) ─────────────────────
      for (final g in _invitationService.joinedGroups) {
        if (!items.any((i) => i.id == g.id) && !leftGroupIds.contains(g.id)) {
          items.add(_GroupItem.fromGroup(g, isDefault: false));
        }
      }

      // ── Accepted invitations → become private group entries ──────
      for (final inv in _invitationService.acceptedInvitations) {
        if (!items.any((i) => i.id == inv.groupId) && !leftGroupIds.contains(inv.groupId)) {
          items.add(_GroupItem(
            id: inv.groupId,
            name: inv.groupName,
            description: inv.groupDescription,
            imageUrl: inv.groupImageUrl,
            memberCount: 0,
            category: 'PRIVATE',
            isDefault: false,
            isImageLocked: false,
            privacy: GroupPrivacy.private_,
            lastMessage: '${inv.invitedByName}: Welcome to the group!',
            lastSenderName: inv.invitedByName,
            lastMessageTime: inv.sentAt,
            unreadCount: 1,
          ));
        }
      }

      // If nothing loaded, leave items empty — no fake demo fallback in production
      // (user will see empty state prompting them to complete onboarding)

      // ── Enrich last-message info from local storage ───────────────
      // Read the actual most-recent message for each group so the list
      // sorts correctly even on first load after the user has chatted.
      await _enrichLastMessages(items);

      setState(() {
        _allGroups = items;
        _pendingInvitations = _invitationService.pendingInvitations;
        _hasLoadError = false;
        _errorMessage = '';
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      // Show error state with empty list — no fake demo data in production
      setState(() {
        _allGroups = [];
        _hasLoadError = true;
        _errorMessage = 'Could not load your groups. Please check your connection.';
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  /// For each group in [items], read its local message storage and update
  /// [lastMessage] / [lastMessageTime] if a newer message exists there.
  /// This makes the list sort correctly immediately after `_loadGroups`.
  Future<void> _enrichLastMessages(List<_GroupItem> items) async {
    for (int i = 0; i < items.length; i++) {
      final group = items[i];
      DateTime? latestTime = group.lastMessageTime;
      String? latestText = group.lastMessage;
      String? latestSender = group.lastSenderName;

      try {
        // User-typed text messages
        final textRaw =
            await BrowserStorage.getString('gc_user_texts_${group.id}');
        if (textRaw != null) {
          final msgs = (json.decode(textRaw) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          for (final m in msgs) {
            final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
            if (ts != null &&
                (latestTime == null || ts.isAfter(latestTime))) {
              latestTime = ts;
              latestText = m['message'] as String?;
              latestSender = 'You';
            }
          }
        }

        // Forwarded / card messages
        final fwdRaw =
            await BrowserStorage.getString('group_messages_${group.id}');
        if (fwdRaw != null) {
          final msgs = (json.decode(fwdRaw) as List<dynamic>)
              .cast<Map<String, dynamic>>();
          for (final m in msgs) {
            final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
            if (ts != null &&
                (latestTime == null || ts.isAfter(latestTime))) {
              latestTime = ts;
              final isMe =
                  (m['senderId'] as String? ?? '') == 'current_user';
              latestSender =
                  isMe ? 'You' : (m['senderName'] as String? ?? '');
              if (m['isMeetupCard'] == true) {
                latestText = '📅 Shared a meetup';
              } else if (m['isGroupCard'] == true) {
                latestText = '👥 Shared a group';
              } else if (m['isEventCard'] == true) {
                latestText = '📌 Shared an event';
              } else if (m['isItemCard'] == true) {
                latestText = '🛍 Shared a listing';
              } else {
                latestText = m['message'] as String?;
              }
            }
          }
        }

        // Media messages (images, documents, location pins)
        final mediaRaw =
            await BrowserStorage.getString('gc_user_media_${group.id}');
        if (mediaRaw != null) {
          final decoded = json.decode(mediaRaw) as Map<String, dynamic>;
          final imgs = (decoded['images'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          final docs = (decoded['documents'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          for (final m in [...imgs, ...docs]) {
            final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
            if (ts != null &&
                (latestTime == null || ts.isAfter(latestTime))) {
              latestTime = ts;
              latestSender = 'You';
              if (m['isLocationPin'] == true) {
                latestText = '📍 Shared a location';
              } else if (m.containsKey('fileName')) {
                latestText = '📄 ${m['fileName']}';
              } else {
                latestText = '📷 Photo';
              }
            }
          }
        }
      } catch (_) {}

      if (latestTime != null &&
          (group.lastMessageTime == null ||
              latestTime.isAfter(group.lastMessageTime!))) {
        final preview = latestSender != null && latestText != null
            ? '$latestSender: $latestText'
            : latestText;
        items[i] = group.copyWith(
          lastMessage: preview,
          lastSenderName: latestSender,
          lastMessageTime: latestTime,
        );
      }
    }
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredGroups = List.from(_allGroups);
      _filteredDMs = List.from(_dmConversations);
      _deepSearchResults = [];
      _isDeepSearching = false;
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredGroups = _allGroups
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              g.description.toLowerCase().contains(q) ||
              g.category.toLowerCase().contains(q))
          .toList();
      _filteredDMs = _dmConversations
          .where((d) =>
              d.recipientName.toLowerCase().contains(q) ||
              (d.lastMessage?.toLowerCase().contains(q) ?? false))
          .toList();

      // Deep search within messages is disabled — search only titles
      _deepSearchResults = [];
      _isDeepSearching = false;
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
      backgroundColor: context.hc.surface,
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
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: isPinned ? 'Unpin' : 'Pin',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(c);
                  setState(() {
                    if (isPinned) {
                      _pinnedGroupIds.remove(group.id);
                    } else {
                      _pinnedGroupIds.add(group.id);
                    }
                    _applyFilter();
                  });
                  _saveMutedAndPinned();
                },
              ),
              _ActionTile(
                icon: isMuted
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                label: isMuted ? 'Unmute' : 'Mute',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(c);
                  setState(() {
                    if (isMuted) {
                      _mutedGroupIds.remove(group.id);
                    } else {
                      _mutedGroupIds.add(group.id);
                    }
                  });
                  _saveMutedAndPinned();
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
              // Archive is only available for user-created groups, not default/listed community groups
              if (!group.isDefault)
                _ActionTile(
                  icon: Icons.archive_outlined,
                  label: 'Archive',
                  onTap: () {
                    Navigator.pop(c);
                    setState(() {
                      _allGroups.removeWhere((g) => g.id == group.id);
                      _applyFilter();
                    });
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('${group.name} archived'),
                        action: SnackBarAction(
                          label: 'Undo',
                          onPressed: () {
                            setState(() {
                              _allGroups.add(group);
                              _applyFilter();
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              // Delete is only available for private group creator/admin
              if (group.isPrivate && group.creatorId == 'current_user')
                _ActionTile(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: HuddlColors.error,
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
              // Leave group — hidden for default groups unless user has changed postcode
              if (!group.isDefault || _onboardingService.hasChangedBorough)
                _ActionTile(
                  icon: Icons.exit_to_app,
                  label: 'Leave group',
                  color: HuddlColors.error,
                  onTap: () {
                    Navigator.pop(c);
                    _confirmLeaveGroup(ctx, group);
                  },
                ),
              const SizedBox(height: 4),
              Divider(height: 1, color: context.hc.divider),
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
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sentiment_dissatisfied_outlined,
                    size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                'Leave this group?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We are sad to see you go, but you can always come back or find another group that interests you in the Discover tab.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
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
                    color: context.hc.divider,
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final onboarding = OnboardingDataService();
                        await onboarding.initialize();
                        final userName = onboarding.name ?? 'You';

                        // 1. Remove from invitation service (joined-via-Discover groups)
                        await _invitationService.leaveGroup(group.id, userName);

                        // 2. Remove from user-created groups storage
                        await _removeFromUserCreatedGroups(group.id);

                        // 3. Remove from DefaultGroupService memberships (default/assigned groups)
                        final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
                        final userId = firebaseUid ?? 'user_${onboarding.name?.hashCode ?? 0}';
                        await _groupService.leaveGroup(userId, group.id);

                        // 4. Persist this group ID so it never gets re-joined on reload
                        await _persistLeftGroup(group.id);

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
                          color: HuddlColors.error,
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

  /// Persist a group ID that the user has explicitly left so it is never
  /// re-assigned on future loads.
  Future<void> _persistLeftGroup(String groupId) async {
    try {
      final ids = await _getLeftGroupIds();
      if (!ids.contains(groupId)) {
        ids.add(groupId);
        await BrowserStorage.setString(_leftGroupsKey, json.encode(ids));
      }
    } catch (_) {}
  }

  /// Return the set of group IDs the user has explicitly left.
  Future<List<String>> _getLeftGroupIds() async {
    try {
      final raw = await BrowserStorage.getString(_leftGroupsKey);
      if (raw == null) return [];
      return List<String>.from(json.decode(raw) as List);
    } catch (_) {
      return [];
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

  /// Navigate to a search result (opens the relevant chat).
  void _navigateToSearchResult(MessageSearchResult result) {
    if (result.isGroup) {
      // Find the group item to get imageUrl
      final group = _allGroups.firstWhere(
        (g) => g.id == result.targetId,
        orElse: () => _GroupItem(
          id: result.targetId,
          name: result.conversationName,
          description: '',
          imageUrl: result.imageUrl,
          memberCount: 0,
          category: '',
          isDefault: false,
          isImageLocked: false,
        ),
      );
      Navigator.pushNamed(context, '/group_chat', arguments: {
        'groupId': group.id,
        'groupName': group.name,
        'groupImageUrl': group.imageUrl,
        'isDefaultGroup': group.isDefault,
        'isPrivate': group.isPrivate,
        'creatorId': group.creatorId,
        'creatorBorough': group.creatorBorough,
        'targetAudience': group.targetAudience,
        'groupCategory': group.category,
        'searchQuery': _searchQuery, // pass query so chat can highlight
      });
    } else {
      Navigator.pushNamed(context, '/dm_chat', arguments: {
        'recipientId': result.targetId,
        'recipientName': result.conversationName,
        'recipientAvatarColor':
            result.recipientAvatarColor ?? '#FF975C',
        'conversationId': result.conversationId,
        'searchQuery': _searchQuery, // pass query so chat can highlight
      });
    }
  }

  /// Format a timestamp for display in search results.
  String _searchTimeFormat(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: HuddlColors.primary),
      );
    }

    final unified = _unifiedMessageList;
    final bool hasDeepResults =
        _searchQuery.isNotEmpty && _deepSearchResults.isNotEmpty;
    final bool isSearchActive = _searchQuery.isNotEmpty;

    // AI suggestions
    final aiSuggestions = _aiService.getPredictiveSuggestions(
      partialQuery: _searchQuery.isEmpty ? null : _searchQuery,
      recentGroupNames: _allGroups.take(5).map((g) => g.name).toList(),
      recentDMNames: _dmConversations.take(5).map((d) => d.recipientName).toList(),
    );

    return Stack(
      children: [
        Column(
          children: [
            // ── AI predictive suggestions (shown when search active but query empty) ─
            if (_showAiSuggestions && _searchQuery.isEmpty && aiSuggestions.isNotEmpty)
              Container(
                color: context.hc.surface,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suggested', style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w500, color: context.hc.textTertiary,
                    )),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: aiSuggestions.take(4).map((s) => GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _searchQuery = s.query;
                            _showAiSuggestions = false;
                            _applyFilter();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(s.icon, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(s.query, style: GoogleFonts.poppins(
                                fontSize: 12, color: HuddlColors.primary, fontWeight: FontWeight.w500,
                              )),
                            ],
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),

            // ── Content area ──────────────────────────────────────────
            Expanded(
              child: isSearchActive
                  ? _buildSearchResults(unified, hasDeepResults)
                  : _buildConversationList(unified),
            ),
          ],
        ),

        // ── Floating compose button ──────────────────────────────────
        if (!isSearchActive)
          Positioned(
            bottom: 24,
            right: 16,
            child: Semantics(
              label: 'New direct message',
              button: true,
              child: Material(
                elevation: 4,
                shadowColor: HuddlColors.primary.withValues(alpha: 0.3),
                shape: const CircleBorder(),
                color: HuddlColors.primary,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pushNamed(context, '/new_dm');
                  },
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // AI Assistant sheet removed — AI is now invisible. Kept for future use.

  /// Build the normal conversation list (no search active).
  Widget _buildAiCatchUpCard() {
    if (!_summariesLoaded) return const SizedBox();
    final groupIds = ['new_parents_cambridge', 'dads_connect', 'toddler_adventures'];
    final activeSummaries = groupIds
        .map((id) => _summariser.getSummary(id))
        .whereType<ChatSummary>()
        .where((s) => !s.isDismissed && s.unreadCount > 10)
        .toList();
    if (activeSummaries.isEmpty) return const SizedBox();
    final summary = activeSummaries.first;

    // ── Compact "Invisible AI" card ──────────────────────────────────────
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.gray200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Unread badge
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.mark_chat_unread_outlined, size: 15, color: HuddlColors.primary),
          ),
          const SizedBox(width: 10),
          // Summary text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${summary.unreadCount} unread in ${summary.groupName}',
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: context.hc.textPrimary,
                  ),
                ),
                Text(
                  summary.overviewText,
                  style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textSecondary, height: 1.3),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Quick jump
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/group_chat', arguments: {
                'groupId': summary.groupId,
                'groupName': summary.groupName,
                'groupImageUrl': '',
                'isDefaultGroup': true,
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('View', style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
              )),
            ),
          ),
          const SizedBox(width: 4),
          // Dismiss
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _summariser.dismissSummary(summary.groupId);
              setState(() {});
            },
            child: Semantics(
              label: 'Dismiss summary',
              button: true,
              child: SizedBox(
                width: 28, height: 28,
                child: Icon(Icons.close, size: 14, color: context.hc.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(List<_MessageListItem> unified) {
    if (unified.isEmpty && _pendingInvitations.isEmpty) {
      return _EmptyMessagesState(onSearch: () {
        // Search is driven by the parent GroupsScreen shared bar — nothing to do here
      });
    }

    return RefreshIndicator(
      onRefresh: _loadGroups,
      color: HuddlColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(top: 2, bottom: 100),
        children: [
          // ── Error banner (P2: user-visible error) ──────────
          if (_hasLoadError)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: HuddlColors.warningBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: HuddlColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: HuddlColors.warningDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage, style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.warningDark,
                    )),
                  ),
                  Semantics(
                    label: 'Retry loading groups',
                    button: true,
                    child: GestureDetector(
                      onTap: _loadGroups,
                      child: Text('Retry', style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.primary,
                      )),
                    ),
                  ),
                ],
              ),
            ),
          // ── AI Catch-Up (compact) ─────────────────────────
          _buildAiCatchUpCard(),
          // ── Pending invitation cards (compact) ──────────────
          if (_pendingInvitations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text('Invitations', style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: context.hc.textTertiary, letterSpacing: 0.3,
              )),
            ),
            ..._pendingInvitations.map((inv) => _InvitationCard(
                  invitation: inv,
                  onAccept: () => _handleAccept(inv),
                  onDecline: () => _handleDecline(inv),
                )),
            const SizedBox(height: 4),
          ],
          // ── Unified rows (groups + DMs, sorted by recent) ──
          ...unified.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final bool isUnread = item.unreadCount > 0;

            // AI insight for this conversation
            final insight = _aiService.getInsightFor(item.id);

            Widget rowWidget;
            if (item.isGroup) {
              rowWidget = _GroupMessageRow(
                group: item.groupItem!,
                isPinned: item.isPinned,
                isMuted: item.isMuted,
                onTap: () {
                  _aiService.recordConversationTap(item.id);
                  Navigator.pushNamed(context, '/group_chat', arguments: {
                    'groupId': item.groupItem!.id,
                    'groupName': item.groupItem!.name,
                    'groupImageUrl': item.groupItem!.imageUrl,
                    'isDefaultGroup': item.groupItem!.isDefault,
                    'isPrivate': item.groupItem!.isPrivate,
                    'creatorId': item.groupItem!.creatorId,
                    'creatorBorough': item.groupItem!.creatorBorough,
                    'targetAudience': item.groupItem!.targetAudience,
                    'groupCategory': item.groupItem!.category,
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
                  _aiService.recordConversationTap(item.id);
                  // Clear Firestore unread badge immediately on tap
                  if (item.dmConversation!.id.startsWith('conv_')) {
                    _realtimeDMService.markConversationRead(
                        item.dmConversation!.id);
                  }
                  Navigator.pushNamed(context, '/dm_chat', arguments: {
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
                  swipeLeftLabel: item.isGroup ? 'Leave' : 'Delete',
                  swipeLeftIcon: item.isGroup ? Icons.exit_to_app : Icons.delete,
                  onDelete: () {
                    if (item.isGroup && item.groupItem != null) {
                      if (item.groupItem!.isDefault && !_onboardingService.hasChangedBorough) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Default borough groups can only be left after a postcode change.'),
                            backgroundColor: HuddlColors.textDark,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                        return;
                      }
                      _confirmLeaveGroup(context, item.groupItem!);
                    } else {
                      _confirmDeleteConversation(context, item);
                    }
                  },
                  onToggleRead: () => _toggleReadStatus(item),
                  child: rowWidget,
                ),
                // AI insight badge (subtle, below the row)
                if (insight != null && insight.category == 'reply_needed')
                  Container(
                    margin: const EdgeInsets.only(left: 80, right: 16, bottom: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 4, height: 4,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(insight.insightText, style: GoogleFonts.poppins(
                          fontSize: 10, color: HuddlColors.primary.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        )),
                        const Spacer(),
                        // Feedback buttons
                        _AiFeedbackRow(
                          onThumbsUp: () {
                            _aiService.recordFeedback(AiMessageFeedback(
                              suggestionId: 'insight_${item.id}',
                              isPositive: true,
                            ));
                            setState(() {});
                          },
                          onThumbsDown: () {
                            _aiService.recordFeedback(AiMessageFeedback(
                              suggestionId: 'insight_${item.id}',
                              isPositive: false,
                            ));
                            // Remove insight on negative feedback
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                if (index < unified.length - 1)
                  Divider(height: 1, indent: 80, color: context.hc.divider),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// Build search results view with conversation matches + deep message matches.
  Widget _buildSearchResults(
      List<_MessageListItem> conversationMatches, bool hasDeepResults) {
    // Group deep results by conversation
    final Map<String, List<MessageSearchResult>> groupedDeep = {};
    for (final r in _deepSearchResults) {
      groupedDeep.putIfAbsent(r.conversationId, () => []).add(r);
    }

    // Determine which conversations matched by name (already in conversationMatches)
    final matchedConvIds =
        conversationMatches.map((m) => m.id).toSet();

    // Deep-only conversations: have message matches but not in name matches
    final deepOnlyConvIds = groupedDeep.keys
        .where((id) => !matchedConvIds.contains(id))
        .toList();

    final bool noResults = conversationMatches.isEmpty &&
        !hasDeepResults &&
        !_isDeepSearching;

    if (noResults) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.search_off,
                    size: 32, color: HuddlColors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: context.hc.textTertiary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      children: [
        // ── Section: Conversations matching by name ──────────────
        if (conversationMatches.isNotEmpty) ...[
          _SearchSectionHeader(
            title: 'Chats',
            count: conversationMatches.length,
          ),
          ...conversationMatches.asMap().entries.map((entry) {
            final item = entry.value;
            Widget rowWidget;
            if (item.isGroup) {
              rowWidget = _GroupMessageRow(
                group: item.groupItem!,
                isPinned: item.isPinned,
                isMuted: item.isMuted,

                onTap: () {
                  Navigator.pushNamed(context, '/group_chat', arguments: {
                    'groupId': item.groupItem!.id,
                    'groupName': item.groupItem!.name,
                    'groupImageUrl': item.groupItem!.imageUrl,
                    'isDefaultGroup': item.groupItem!.isDefault,
                    'isPrivate': item.groupItem!.isPrivate,
                    'creatorId': item.groupItem!.creatorId,
                    'creatorBorough': item.groupItem!.creatorBorough,
                    'targetAudience': item.groupItem!.targetAudience,
                    'groupCategory': item.groupItem!.category,
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
                  Navigator.pushNamed(context, '/dm_chat', arguments: {
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

            // Show deep message matches under this conversation
            final convDeepResults = groupedDeep[item.id];
            return Column(
              children: [
                rowWidget,
                if (convDeepResults != null && convDeepResults.isNotEmpty)
                  ...convDeepResults.take(3).map((r) =>
                      _DeepSearchResultRow(
                        result: r,
                        query: _searchQuery,
                        timeFormat: _searchTimeFormat,
                        onTap: () => _navigateToSearchResult(r),
                      )),
                if (convDeepResults != null && convDeepResults.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 80, right: 16, bottom: 8),
                    child: GestureDetector(
                      onTap: () => _navigateToSearchResult(
                          convDeepResults.first),
                      child: Text(
                        '${convDeepResults.length - 3} more results in this chat',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                Divider(
                    height: 1, indent: 80, color: context.hc.divider),
              ],
            );
          }),
        ],

        // ── Section: Messages matching within other conversations ──
        if (deepOnlyConvIds.isNotEmpty) ...[
          _SearchSectionHeader(
            title: 'Messages',
            count: deepOnlyConvIds.fold<int>(
                0, (s, id) => s + (groupedDeep[id]?.length ?? 0)),
          ),
          ...deepOnlyConvIds.map((convId) {
            final results = groupedDeep[convId]!;
            final first = results.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Conversation header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      if (first.isGroup)
                        _GroupAvatar(
                            imageUrl: first.imageUrl,
                            groupName: first.conversationName,
                            groupId: first.targetId,
                            size: 28)
                      else
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              _dmColorFromHex(first.avatarColor),
                          child: Text(
                            first.conversationName.isNotEmpty
                                ? first.conversationName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          first.conversationName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: HuddlColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${results.length}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...results.take(3).map((r) => _DeepSearchResultRow(
                      result: r,
                      query: _searchQuery,
                      timeFormat: _searchTimeFormat,
                      onTap: () => _navigateToSearchResult(r),
                    )),
                if (results.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 80, right: 16, bottom: 8),
                    child: GestureDetector(
                      onTap: () =>
                          _navigateToSearchResult(results.first),
                      child: Text(
                        '${results.length - 3} more results',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                Divider(
                    height: 1, indent: 16, color: context.hc.divider),
              ],
            );
          }),
        ],

        // ── Loading indicator for deep search ──────────────────────
        if (_isDeepSearching)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: HuddlColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Searching within messages...',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── No conversation matches but deep search still running ──
        if (conversationMatches.isEmpty &&
            !hasDeepResults &&
            _isDeepSearching)
          const SizedBox(height: 40),
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
      // DM: use Firestore service for real convs, local service for demo
      if (item.unreadCount > 0) {
        if (item.id.startsWith('conv_')) {
          _realtimeDMService.markConversationRead(item.id);
        } else {
          _dmService.markConversationRead(item.id);
        }
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
    // Public groups cannot be deleted — redirect to leave flow
    if (item.isGroup && !item.isPrivate && item.groupItem != null) {
      _confirmLeaveGroup(ctx, item.groupItem!);
      return;
    }
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
                  color: context.hc.textPrimary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
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
                          color: context.hc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
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
                          color: HuddlColors.error,
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
      backgroundColor: context.hc.surface,
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
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: isPinned ? 'Unpin' : 'Pin',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(c);
                  setState(() {
                    if (isPinned) {
                      _pinnedGroupIds.remove(dm.id);
                    } else {
                      _pinnedGroupIds.add(dm.id);
                    }
                    _applyFilter();
                  });
                  _saveMutedAndPinned();
                },
              ),
              _ActionTile(
                icon: isMuted
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                label: isMuted ? 'Unmute' : 'Mute',
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(c);
                  setState(() {
                    if (isMuted) {
                      _mutedGroupIds.remove(dm.id);
                    } else {
                      _mutedGroupIds.add(dm.id);
                    }
                  });
                  _saveMutedAndPinned();
                  // Also sync with DMService
                  _dmService.toggleMute(dm.id);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(isMuted ? '${dm.recipientName} unmuted' : '${dm.recipientName} muted'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
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
                    // Clear Firestore unread for real conversations
                    if (dm.id.startsWith('conv_')) {
                      await _realtimeDMService.markConversationRead(dm.id);
                    } else {
                      await _dmService.markConversationRead(dm.id);
                    }
                  } else {
                    await _dmService.markConversationUnread(dm.id);
                  }
                },
              ),
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: HuddlColors.error,
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
              Divider(height: 1, color: context.hc.divider),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isPinned ? HuddlColors.white : HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // ── Group avatar (scenic image or fallback) ──────────
                _GroupAvatar(
                  imageUrl: group.imageUrl,
                  groupName: group.name,
                  groupId: group.id,
                  size: 54,
                  isOnline: hasUnread,
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
                                      color: context.hc.textPrimary,
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
                                      color: context.hc.textTertiary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Private Group',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: context.hc.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.notifications_off,
                                size: 14, color: context.hc.textTertiary),
                          ],
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(group.lastMessageTime),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: hasUnread ? HuddlColors.primary : context.hc.textTertiary,
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
                                color: hasUnread ? HuddlColors.textSecondary : context.hc.textTertiary,
                                fontWeight:
                                    hasUnread ? FontWeight.w500 : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            Semantics(
                              label: '${group.unreadCount} unread messages',
                              child: Container(
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
                                    color: context.hc.surface,
                                  ),
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
        color: context.hc.surface,
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
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildGroupImage(invitation.groupImageUrl),
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
                              color: context.hc.textPrimary,
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
                        color: context.hc.textTertiary,
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
                color: context.hc.textSecondary,
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
                      side: BorderSide(color: context.hc.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.center,
                    ),
                    child: Text(
                      'Decline',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.hc.textSecondary,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
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
                      padding: EdgeInsets.zero,
                      alignment: Alignment.center,
                    ),
                    child: Text(
                      'Accept',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.hc.surface,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
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

  /// Build group image — handles data:base64, http/https URLs, asset paths
  Widget _buildGroupImage(String imageUrl) {
    if (imageUrl.isEmpty) {
      return const Icon(Icons.group_add, size: 24, color: HuddlColors.primary);
    }

    // Data URL (base64 image from image picker)
    if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(imageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: 48,
            height: 48,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.group_add, size: 24, color: HuddlColors.primary),
          );
        }
      } catch (_) {}
      return const Icon(Icons.group_add, size: 24, color: HuddlColors.primary);
    }

    // Network URL
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.group_add, size: 24, color: HuddlColors.primary),
      );
    }

    // Asset path
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.group_add, size: 24, color: HuddlColors.primary),
      );
    }

    return const Icon(Icons.group_add, size: 24, color: HuddlColors.primary);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isPinned ? HuddlColors.white : HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // ── Person avatar with profile photo ──────────────
                MemberAvatar(
                  name: conversation.recipientName,
                  imageUrl: conversation.recipientPhotoUrl,
                  size: 54,
                  accentColor: color,
                  showOnlineDot: true,
                  isOnline: DMService().isUserOnline(conversation.recipientId),
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
                                color: context.hc.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.notifications_off,
                                size: 14, color: context.hc.textTertiary),
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
                            Semantics(
                              label: '${conversation.unreadCount} unread messages',
                              child: Container(
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
                                    color: context.hc.surface,
                                  ),
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

/// Palette of distinct background colors used for initials-based avatars.
/// Chosen to be visually distinct from each other and readable against white text.
const List<Color> _kAvatarPalette = [
  Color(0xFFE57373), // red
  Color(0xFFFF8A65), // deep orange
  Color(0xFFFFB74D), // orange
  Color(0xFFFFD54F), // amber
  Color(0xFFA5D6A7), // green
  Color(0xFF4DB6AC), // teal
  Color(0xFF4FC3F7), // light blue
  Color(0xFF7986CB), // indigo
  Color(0xFFBA68C8), // purple
  Color(0xFFF06292), // pink
  Color(0xFF90A4AE), // blue grey
  Color(0xFF80CBC4), // teal light
  Color(0xFFCE93D8), // purple light
  Color(0xFF80DEEA), // cyan
  Color(0xFFFFCC02), // yellow
  Color(0xFF66BB6A), // green darker
];

/// Pick a deterministic color from the palette using the group id or name.
Color _avatarColorForGroup(String seed) {
  if (seed.isEmpty) return _kAvatarPalette[0];
  int hash = 0;
  for (final c in seed.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  return _kAvatarPalette[hash % _kAvatarPalette.length];
}

/// Extract up to 2 initials from a group name for the fallback avatar.
/// e.g. "Cambridge Parents 2024" → "CP"
/// e.g. "Dads Connect" → "DC"
/// e.g. "SEN Support" → "SS"
String _initialsForGroup(String name) {
  if (name.isEmpty) return '?';
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length == 1) {
    return words[0].substring(0, words[0].length.clamp(1, 2)).toUpperCase();
  }
  // Take first letter of first two significant words (skip short words like "the", "a")
  final significant = words.where((w) => w.length > 1).toList();
  if (significant.isEmpty) return words[0][0].toUpperCase();
  if (significant.length == 1) return significant[0].substring(0, significant[0].length.clamp(1, 2)).toUpperCase();
  return '${significant[0][0]}${significant[1][0]}'.toUpperCase();
}

class _GroupAvatar extends StatelessWidget {
  final String imageUrl;
  final String groupName;
  final String groupId;
  final double size;
  final bool isOnline;

  const _GroupAvatar({
    required this.imageUrl,
    this.groupName = '',
    this.groupId = '',
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
            color: HuddlColors.primary.withValues(alpha: 0.08),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildImage(),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Semantics(
              label: 'New messages available',
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _kOnline,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.hc.surface, width: 2),
                ),
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
        errorBuilder: (_, __, ___) => _initialsAvatar(),
      );
    } else if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _initialsAvatar(),
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
            errorBuilder: (_, __, ___) => _initialsAvatar(),
          );
        }
      } catch (_) {
        // fall through
      }
    }
    // No valid image URL — show unique initials avatar
    return _initialsAvatar();
  }

  /// Generates a unique, deterministic initials-based avatar so every group
  /// looks distinct even when no imageUrl is stored in Firestore.
  Widget _initialsAvatar() {
    final seed = groupId.isNotEmpty ? groupId : groupName;
    final bgColor = _avatarColorForGroup(seed);
    final initials = _initialsForGroup(groupName);
    final fontSize = size * (initials.length > 1 ? 0.30 : 0.38);

    return Container(
      width: size,
      height: size,
      color: bgColor,
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.poppins(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
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
  const _DiscoverTab({
    super.key,
    required this.groupsChangedNotifier,
  });

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  String _searchQuery = '';
  String _selectedSort = 'Recommended';
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();


  // ── Filter states ─────────────────────────────────────────────────
  Set<String> _selectedAudiences = {};

  // ── Services ──────────────────────────────────────────────────────
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final InvitationService _invitationService = InvitationService();
  final DiscoverAiService _discoverAi = DiscoverAiService();
  String? _userParentType;
  List<String> _userStagesOfLife = [];
  String? _userBorough;
  bool _hasLoadError = false;

  // ── Invisible AI state ────────────────────────────────────────────
  bool _aiRecommendationsEnabled = true; // human override toggle
  List<DiscoverSearchSuggestion> _aiSuggestions = [];
  bool _showAiContextBanner = true; // contextual personalisation banner above group list

  @override
  void initState() {
    super.initState();
    // Defer all work and listener registration to after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.groupsChangedNotifier.addListener(_onGroupsChanged);
      _loadUserProfile();
      _discoverAi.initialize().then((_) {
        if (mounted) {
          setState(() {
            _aiSuggestions = _discoverAi.getPredictiveSuggestions(
              userBorough: _userBorough,
              stagesOfLife: _userStagesOfLife,
              parentType: _userParentType,
            );
          });
        }
      });
    });
  }

  @override
  void dispose() {
    widget.groupsChangedNotifier.removeListener(_onGroupsChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Called from EventsScreen AppBar to open search mode.
  void activateSearch() {
    setState(() => _isSearchActive = true);
    // Focus is requested after the frame so the field is built first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  /// Called when the user navigates away from the Groups tab — resets to card view.
  void deactivateSearch() {
    if (!_isSearchActive) return;
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
    });
  }

  void _onGroupsChanged() {
    // Reload user-created groups when notified
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
    try {
      await _onboardingService.initialize();
      await _invitationService.initialize();
      await _loadUserCreatedGroups();
      if (mounted) {
        setState(() {
          _userParentType = _onboardingService.parentType;
          _userStagesOfLife = _onboardingService.stagesOfLife;
          final postcode = _onboardingService.postcode;
          _userBorough = PostcodeService().getBoroughFromPostcode(postcode);
          _hasLoadError = false;
          // Refresh AI suggestions with profile data
          _aiSuggestions = _discoverAi.getPredictiveSuggestions(
            userBorough: _userBorough,
            stagesOfLife: _userStagesOfLife,
            parentType: _userParentType,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasLoadError = true);
      }
    }
  }


  /// Load user-created groups from local storage and add them to
  /// the discover list. Public groups are visible to same-borough users.
  /// Private groups are visible only to the creator and invited members.
  Future<void> _loadUserCreatedGroups() async {
    try {
      final raw = await BrowserStorage.getString(_userGroupsKey);
      if (raw == null) return;
      final List<dynamic> decoded = json.decode(raw);
      for (final j in decoded) {
        final g = Group.fromJson(j as Map<String, dynamic>);
        // Avoid duplicates
        if (!_allDiscoverGroups.any((d) => d.id == g.id)) {
          _allDiscoverGroups.add(_GroupItem.fromGroup(g, isDefault: false));
        }
      }
    } catch (_) {
      // Silently ignore storage read failures
    }
  }

  final List<_GroupItem> _allDiscoverGroups = [
    // ── GENERAL / POPULAR ──────────────────────────────────────────────────
    _GroupItem(
      id: 'disc_first_time_mums',
      name: 'First Time Mums',
      description:
          'A supportive community for first-time mothers navigating the joys and challenges of new parenthood.',
      imageUrl:
          'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=800&q=80',
      memberCount: 1247,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
      aiTagline: 'Your village for the beautiful, messy first year of motherhood.',
    ),
    _GroupItem(
      id: 'disc_dads_connect',
      name: 'Dads Connect',
      description:
          'A space for dads to share experiences, ask questions, and support each other through every stage of fatherhood.',
      imageUrl:
          'https://images.unsplash.com/photo-1531983412531-1f49a365ffed?w=800&q=80',
      memberCount: 834,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Dads'],
      aiTagline: 'Real dads, real questions — judgement-free fatherhood support.',
    ),
    _GroupItem(
      id: 'disc_bump_to_baby',
      name: 'Bump to Baby',
      description:
          'From the first scan to those precious early weeks — share your pregnancy and newborn journey with parents at the same stage.',
      imageUrl:
          'https://images.unsplash.com/photo-1544126592-807ade215a0b?w=800&q=80',
      memberCount: 1105,
      category: 'PREGNANCY',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Parents expecting a baby'],
      aiTagline: 'From first scan to first smile — share every stage together.',
    ),
    _GroupItem(
      id: 'disc_pregnancy_antenatal',
      name: 'Pregnancy & Antenatal',
      description:
          'Antenatal advice, birth preparation, hospital bag checklists, and real talk from Cambridge parents who\'ve been there.',
      imageUrl:
          'https://images.unsplash.com/photo-1516627145497-ae6968895b74?w=800&q=80',
      memberCount: 892,
      category: 'PREGNANCY',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Parents expecting a baby'],
      aiTagline: 'Honest birth prep and antenatal advice from those who\'ve done it.',
    ),
    _GroupItem(
      id: 'disc_newborn_club',
      name: 'Newborn Club',
      description:
          'For parents of babies 0–3 months. Sleepless nights, feeding worries, and all the tiny milestones worth celebrating together.',
      imageUrl:
          'https://images.unsplash.com/photo-1519689680058-324335c77eba?w=800&q=80',
      memberCount: 763,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Sleepless nights, big love — 0–3 months survival support.',
    ),
    _GroupItem(
      id: 'disc_single_parents',
      name: 'Single Parents Cambridge',
      description:
          'A warm, judgement-free space for solo parents to share advice, find playdates and support each other in Cambridge.',
      imageUrl:
          'https://images.unsplash.com/photo-1476703993599-0035a21b17a9?w=800&q=80',
      memberCount: 541,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Solo parenting is hard — but you don\'t have to do it alone.',
    ),
    _GroupItem(
      id: 'disc_lgbtq_parents',
      name: 'LGBTQ+ Parents Cambridge',
      description:
          'A welcoming community for LGBTQ+ parents and families in Cambridge to connect, share and support each other.',
      imageUrl:
          'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&q=80',
      memberCount: 318,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Inclusive, proud and connected — all families welcome here.',
    ),
    _GroupItem(
      id: 'disc_adoption_fostering',
      name: 'Adoption & Fostering Families',
      description:
          'Support and community for adoptive and foster families in Cambridge — navigating paperwork, bonding and everything in between.',
      imageUrl:
          'https://images.unsplash.com/photo-1604079628040-94301bb21b91?w=800&q=80',
      memberCount: 224,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Navigating adoption and fostering with community at your side.',
    ),

    // ── LANGUAGE & CULTURAL ───────────────────────────────────────────────
    _GroupItem(
      id: 'disc_dutch_parents',
      name: 'Dutch-speaking Parents',
      description:
          'Een groep voor Nederlandstalige ouders in Cambridge — deel tips, organiseer speelafspraken en voel je thuis.',
      imageUrl:
          'https://images.unsplash.com/photo-1468421870903-4df1664ac249?w=800&q=80',
      memberCount: 187,
      category: 'LANGUAGE & CULTURE',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Dutch families in Cambridge — tips, play dates and a taste of home.',
    ),
    _GroupItem(
      id: 'disc_german_parents',
      name: 'German-speaking Parents',
      description:
          'Eine Gemeinschaft für deutschsprachige Eltern in Cambridge — Tipps, Spielgruppen und ein Stück Heimat.',
      imageUrl:
          'https://images.unsplash.com/photo-1528360983277-13d401cdc186?w=800&q=80',
      memberCount: 203,
      category: 'LANGUAGE & CULTURE',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'German families in Cambridge — Spielgruppen, Tipps und echte Verbindung.',
    ),

    // ── SLEEP & FEEDING ───────────────────────────────────────────────────
    _GroupItem(
      id: 'disc_baby_sleep',
      name: 'Baby Sleep Solutions',
      description:
          'Tips, routines and real-parent advice for getting your baby to sleep. From newborn schedules to sleep training methods — we\'ve tried it all.',
      imageUrl:
          'https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?w=800&q=80',
      memberCount: 2156,
      category: 'SLEEP',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Finally get some sleep — routines and real advice that actually work.',
    ),
    _GroupItem(
      id: 'disc_breastfeeding',
      name: 'Breastfeeding Support',
      description:
          'A safe, supportive space for breastfeeding questions, latch issues, supply worries, and celebrating every milestone along the way.',
      imageUrl:
          'https://images.unsplash.com/photo-1492725764893-90b379c2b6e7?w=800&q=80',
      memberCount: 1382,
      category: 'FEEDING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
      aiTagline: 'Latch help, supply questions and feeding wins — no judgement here.',
    ),
    _GroupItem(
      id: 'disc_weaning_first_foods',
      name: 'Weaning & First Foods',
      description:
          'Everything you need for starting solids — BLW vs purée, first food ideas, allergies, gagging vs choking, and recipe inspiration for tiny eaters.',
      imageUrl:
          'https://images.unsplash.com/photo-1490645935967-10de6ba17061?w=800&q=80',
      memberCount: 1674,
      category: 'FEEDING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'BLW or purée? First foods made easy with real-parent recipes.',
    ),
    _GroupItem(
      id: 'disc_child_nutrition',
      name: 'Child Nutrition & Feeding',
      description:
          'Beyond weaning — navigating fussy eaters, packed lunches, school meals, healthy snacks and raising children with a positive relationship with food.',
      imageUrl:
          'https://images.unsplash.com/photo-1466637574441-749b8f19452f?w=800&q=80',
      memberCount: 897,
      category: 'FOOD & NUTRITION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Fussy eaters, packed lunches and building healthy food habits for life.',
    ),
    _GroupItem(
      id: 'disc_healthy_meals',
      name: 'Healthy Family Meals',
      description:
          'Share recipes, meal plans and ideas for nutritious, family-friendly meals that even the pickiest toddler might actually eat.',
      imageUrl:
          'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800&q=80',
      memberCount: 1589,
      category: 'FOOD & NUTRITION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Nutritious family recipes that even the pickiest toddler will try.',
    ),
    _GroupItem(
      id: 'disc_allergies_dietary',
      name: 'Allergies & Dietary Needs',
      description:
          'Support for families managing food allergies, intolerances and special dietary requirements — from diagnosis to navigating school and social situations.',
      imageUrl:
          'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=800&q=80',
      memberCount: 614,
      category: 'FOOD & NUTRITION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Managing allergies from diagnosis to school — you\'re not alone.',
    ),

    // ── EDUCATION & LEARNING ──────────────────────────────────────────────
    _GroupItem(
      id: 'disc_montessori_parenting',
      name: 'Montessori Parenting',
      description:
          'Explore the Montessori philosophy at home — practical activities, prepared environment ideas, and how to follow your child\'s natural curiosity.',
      imageUrl:
          'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&q=80',
      memberCount: 743,
      category: 'EDUCATION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Follow your child\'s curiosity — Montessori ideas for the home.',
    ),
    _GroupItem(
      id: 'disc_forest_school',
      name: 'Forest School & Outdoor Play',
      description:
          'Mud kitchens, bug hunts, den building and risky play — celebrating outdoor, nature-based learning for Cambridge children.',
      imageUrl:
          'https://images.unsplash.com/photo-1472162072942-cd5147eb3902?w=800&q=80',
      memberCount: 562,
      category: 'EDUCATION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Mud, bugs and dens — nature-based learning for Cambridge kids.',
    ),
    _GroupItem(
      id: 'disc_home_education',
      name: 'Home Education Cambridge',
      description:
          'A community for home educating families in Cambridge — curriculum ideas, group learning days, local resources and legal guidance.',
      imageUrl:
          'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80',
      memberCount: 389,
      category: 'EDUCATION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Curriculum ideas, local resources and community for home educators.',
    ),
    _GroupItem(
      id: 'disc_baby_sign_language',
      name: 'Baby Sign Language',
      description:
          'Reduce frustration and boost communication with baby signing. Share signs, videos, progress and resources for signing with babies and toddlers.',
      imageUrl:
          'https://images.unsplash.com/photo-1565043666747-69f6646db940?w=800&q=80',
      memberCount: 418,
      category: 'EDUCATION',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Help your baby communicate before words — signs that transform tantrums.',
    ),

    // ── ACTIVITIES & PLAY ─────────────────────────────────────────────────
    _GroupItem(
      id: 'disc_baby_sensory',
      name: 'Baby Sensory Play',
      description:
          'DIY sensory activities, play ideas and inspiration for stimulating your baby\'s development through sight, touch, sound and movement.',
      imageUrl:
          'https://images.unsplash.com/photo-1596461404969-9ae70f2830c1?w=800&q=80',
      memberCount: 976,
      category: 'PLAY & ACTIVITIES',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'DIY sensory play ideas that light up your baby\'s developing brain.',
    ),
    _GroupItem(
      id: 'disc_toddler_activities',
      name: 'Toddler Activities Cambridge',
      description:
          'What\'s on for toddlers in Cambridge? Share the best classes, playgroups, soft plays and activity ideas for 1–4 year olds.',
      imageUrl:
          'https://images.unsplash.com/photo-1543248939-ff40856f65d4?w=800&q=80',
      memberCount: 1843,
      category: 'PLAY & ACTIVITIES',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Best classes, soft plays and playgroups for Cambridge toddlers.',
    ),
    _GroupItem(
      id: 'disc_cambridge_playgrounds',
      name: 'Cambridge Playgrounds & Parks',
      description:
          'Rate, review and discover the best playgrounds, parks and outdoor spaces in Cambridge for children of all ages.',
      imageUrl:
          'https://images.unsplash.com/photo-1575783970733-1aaedde1db74?w=800&q=80',
      memberCount: 1267,
      category: 'PLAY & ACTIVITIES',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Discover Cambridge\'s best parks and playgrounds, rated by local parents.',
    ),

    // ── FITNESS & SPORT ───────────────────────────────────────────────────
    _GroupItem(
      id: 'disc_buggy_runners',
      name: 'Buggy Runners & Active Parents',
      description:
          'Running with your buggy, pram workouts, buggy bootcamp and staying active as a parent in Cambridge. All abilities welcome.',
      imageUrl:
          'https://images.unsplash.com/photo-1571008887538-b36bb32f4571?w=800&q=80',
      memberCount: 634,
      category: 'FITNESS',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Run, pram and all — stay active with your baby in Cambridge.',
    ),
    _GroupItem(
      id: 'disc_postnatal_fitness',
      name: 'Postnatal Fitness',
      description:
          'Safely rebuild your strength and fitness after pregnancy with expert advice, community support and local class recommendations.',
      imageUrl:
          'https://images.unsplash.com/photo-1518310383802-640c2de311b2?w=800&q=80',
      memberCount: 967,
      category: 'FITNESS',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
      aiTagline: 'Rebuild strength safely after birth — expert advice and real support.',
    ),
    _GroupItem(
      id: 'disc_postnatal_yoga',
      name: 'Postnatal Yoga & Pilates',
      description:
          'Gentle yoga and pilates for new mums — pelvic floor recovery, stress relief, and finding calm in the chaos of early parenthood.',
      imageUrl:
          'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=800&q=80',
      memberCount: 712,
      category: 'FITNESS',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
      aiTagline: 'Gentle movement for new mums — pelvic floor, calm and recovery.',
    ),
    _GroupItem(
      id: 'disc_buggy_bootcamp',
      name: 'Buggy Bootcamp Cambridge',
      description:
          'Outdoor group fitness sessions designed for parents — bring your buggy and join the workout. Fun, sociable and effective.',
      imageUrl:
          'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=800&q=80',
      memberCount: 489,
      category: 'FITNESS',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Outdoor workouts with your buggy — sociable, fun and effective.',
    ),
    _GroupItem(
      id: 'disc_cambridge_tennis',
      name: 'Cambridge Tennis Families',
      description:
          'Connect with tennis-playing families in Cambridge — junior coaching recommendations, club memberships, social matches and family tennis events.',
      imageUrl:
          'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?w=800&q=80',
      memberCount: 356,
      category: 'SPORT',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Junior coaching, club tips and family tennis events in Cambridge.',
    ),
    _GroupItem(
      id: 'disc_cambridge_sports',
      name: 'Cambridge Sports Families',
      description:
          'Football, swimming, gymnastics, cricket and more — a hub for sports-mad families in Cambridge to share clubs, fixtures and encourage young athletes.',
      imageUrl:
          'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=800&q=80',
      memberCount: 921,
      category: 'SPORT',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Clubs, fixtures and cheerleading for Cambridge\'s young sports stars.',
    ),

    // ── WELLBEING & SUPPORT ───────────────────────────────────────────────
    _GroupItem(
      id: 'disc_mental_health',
      name: 'Parent Mental Health & Wellbeing',
      description:
          'A kind, non-judgemental space to talk about parental anxiety, postnatal depression, burnout and looking after yourself so you can look after others.',
      imageUrl:
          'https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=800&q=80',
      memberCount: 874,
      category: 'WELLBEING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Your mental health matters too — kind, honest and judgement-free.',
    ),
    _GroupItem(
      id: 'disc_nct_cambridge',
      name: 'NCT Cambridge',
      description:
          'Connect with other NCT Cambridge parents — whether you\'re in a group now or looking to stay in touch after classes have ended.',
      imageUrl:
          'https://images.unsplash.com/photo-1491013516836-7db643ee125a?w=800&q=80',
      memberCount: 1521,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Parents expecting a baby'],
      aiTagline: 'Stay connected with your NCT Cambridge group long after classes end.',
    ),
    _GroupItem(
      id: 'disc_special_needs_send',
      name: 'Special Needs & SEND Support',
      description:
          'Support, resources and community for families of children with additional needs, disabilities and SEND in Cambridge.',
      imageUrl:
          'https://images.unsplash.com/photo-1509909756405-be0199881695?w=800&q=80',
      memberCount: 467,
      category: 'WELLBEING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Resources, advocacy and community for SEND families in Cambridge.',
    ),
    _GroupItem(
      id: 'disc_parents_multiples',
      name: 'Parents of Multiples',
      description:
          'Twins, triplets and beyond! Share the beautiful chaos of raising multiples — double the love, double the advice.',
      imageUrl:
          'https://images.unsplash.com/photo-1519340241574-2cec6aef0c01?w=800&q=80',
      memberCount: 298,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Twins, triplets and beyond — double the love, double the support.',
    ),
    _GroupItem(
      id: 'disc_dad_baby',
      name: 'Dad & Baby Groups',
      description:
          'Dedicated groups, classes and meetups for dads and their babies in Cambridge. No mums required — just dads doing the dad thing.',
      imageUrl:
          'https://images.unsplash.com/photo-1474524955719-b9f87c50ce47?w=800&q=80',
      memberCount: 412,
      category: 'PARENTING',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Dads'],
      aiTagline: 'Just dads and babies — classes, meetups and no need to explain yourself.',
    ),

    // ── CHILDCARE & PRACTICALITIES ────────────────────────────────────────
    _GroupItem(
      id: 'disc_nanny_share',
      name: 'Nanny Share & Childminder Network',
      description:
          'Find nanny share partners, recommend trusted childminders, and navigate the Cambridge childcare landscape together.',
      imageUrl:
          'https://images.unsplash.com/photo-1587654780291-39c9404d746b?w=800&q=80',
      memberCount: 687,
      category: 'CHILDCARE',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Find nanny share partners and trusted childminders in Cambridge.',
    ),
    _GroupItem(
      id: 'disc_back_to_work',
      name: 'Back to Work Mums',
      description:
          'Returning to work after maternity leave? Share childcare solutions, flexible working wins, imposter syndrome and the juggle of career + family.',
      imageUrl:
          'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=800&q=80',
      memberCount: 834,
      category: 'WORK-LIFE',
      isDefault: false,
      isImageLocked: false,
      targetAudience: ['Mums'],
      aiTagline: 'Returning after maternity leave — flexible work wins and real talk.',
    ),
    _GroupItem(
      id: 'disc_working_parents',
      name: 'Working Parents Network',
      description:
          'Balancing work and family life. Share tips on flexible working, childcare and career progression as a Cambridge parent.',
      imageUrl:
          'https://images.unsplash.com/photo-1521791136064-7986c2920216?w=800&q=80',
      memberCount: 743,
      category: 'WORK-LIFE',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Flexible work, childcare and career — the Cambridge parent juggle.',
    ),
    _GroupItem(
      id: 'disc_child_sleep_consultants',
      name: 'Sleep Consultants & Sleep Training',
      description:
          'Discuss sleep consultant experiences, sleep training methods (CIO, Ferber, gentle), and share what actually worked for your family.',
      imageUrl:
          'https://images.unsplash.com/photo-1512069772995-ec65ed45afd6?w=800&q=80',
      memberCount: 543,
      category: 'SLEEP',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'CIO, Ferber or gentle — share what sleep method actually worked.',
    ),

    // ── LIFESTYLE ─────────────────────────────────────────────────────────
    _GroupItem(
      id: 'disc_eco_parenting',
      name: 'Eco Parenting Cambridge',
      description:
          'Cloth nappies, plastic-free toys, sustainable baby products and raising children with a love of the natural world.',
      imageUrl:
          'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?w=800&q=80',
      memberCount: 521,
      category: 'LIFESTYLE',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Cloth nappies, plastic-free play and raising planet-conscious kids.',
    ),
    _GroupItem(
      id: 'disc_travel_tribe',
      name: 'Travel Tribe',
      description:
          'Share travel advice and real experiences — from kid-friendly destinations and flight survival tips to honest hotel reviews and packing hacks with babies and toddlers.',
      imageUrl:
          'https://images.unsplash.com/photo-1503220317375-aaad61436b1b?w=800&q=80',
      memberCount: 1893,
      category: 'TRAVEL',
      isDefault: false,
      isImageLocked: false,
      aiTagline: 'Flight survival, packing hacks and kid-friendly adventures worldwide.',
    ),
  ];

  /// Check if the current user can open/join a group.
  /// Public: anyone. Group: members of parent group + creator. Private: invited + creator.
  bool _canAccessGroup(_GroupItem g) {
    final isOwnGroup = g.creatorId == 'current_user';
    if (isOwnGroup) return true;

    switch (g.privacy) {
      case GroupPrivacy.public:
        return true;
      case GroupPrivacy.group:
        if (g.parentGroupId == null) return true;
        return _invitationService.isGroupJoined(g.parentGroupId!);
      case GroupPrivacy.private_:
        return g.invitedMemberIds.contains('current_user');
    }
  }

  /// Show restricted-access dialog for private/group groups
  void _showGroupAccessDeniedDialog(BuildContext context, _GroupItem group) {
    final isGroupTier = group.privacy == GroupPrivacy.group;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isGroupTier ? Icons.group : Icons.lock,
              color: HuddlColors.primary,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isGroupTier ? 'Group Members Only' : 'Private Group',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          isGroupTier
              ? 'This group is only open to members of ${group.parentGroupName ?? 'a specific group'}. Join that group first to access this one.'
              : 'This group is private and only open to invited members. Ask the group admin for an invitation.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: context.hc.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_GroupItem> get _filteredGroups {
    List<_GroupItem> results = _allDiscoverGroups.where((g) {
      final isOwnGroup = g.creatorId == 'current_user';
      if (!isOwnGroup && !g.isVisibleTo(_userParentType, _userStagesOfLife)) {
        return false;
      }
      if (!isOwnGroup &&
          g.creatorBorough != null &&
          g.creatorBorough!.isNotEmpty &&
          _userBorough != null) {
        if (g.creatorBorough != _userBorough &&
            g.creatorBorough != 'Unknown Borough') {
          return false;
        }
      }
      return true;
    }).toList();

    // Apply audience filter
    if (_selectedAudiences.isNotEmpty) {
      results = results.where((g) {
        if (g.targetAudience.isEmpty) return true;
        return g.targetAudience.any((a) => _selectedAudiences.contains(a));
      }).toList();
    }

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      // Also apply NLP parsing for natural language queries
      final nlpParams = _discoverAi.parseNaturalQuery(q);
      results = results
          .where((g) =>
              g.name.toLowerCase().contains(q) ||
              g.category.toLowerCase().contains(q) ||
              g.description.toLowerCase().contains(q) ||
              (nlpParams.containsKey('category') &&
                  g.category.toUpperCase() ==
                      (nlpParams['category'] as String).toUpperCase()) ||
              (nlpParams.containsKey('audience') &&
                  g.targetAudience.contains(nlpParams['audience'])))
          .toList();
    }

    // AI-powered recommendation sorting (when sort = 'Recommended' and AI enabled)
    if (_selectedSort == 'Recommended' && _aiRecommendationsEnabled) {
      results.sort((a, b) {
        final sa = _discoverAi.getGroupRecommendationScore(
          a.toJson(),
          userBorough: _userBorough,
          parentType: _userParentType,
          stagesOfLife: _userStagesOfLife,
        );
        final sb = _discoverAi.getGroupRecommendationScore(
          b.toJson(),
          userBorough: _userBorough,
          parentType: _userParentType,
          stagesOfLife: _userStagesOfLife,
        );
        return sb.compareTo(sa);
      });
    } else {
      switch (_selectedSort) {
        case 'Most Members':
          results.sort((a, b) => b.memberCount.compareTo(a.memberCount));
        case 'Newest':
          results = results.reversed.toList();
        case 'A-Z':
          results.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        default:
          break;
      }
    }
    return results;
  }

  Future<void> _onJoinTap(String groupId) async {
    // ── Subscription gate: group join limit ───────────────────────
    final subService = SubscriptionService();
    await subService.initialize();
    if (!subService.canJoinGroup) {
      if (mounted) {
        showUpgradePrompt(
          context,
          feature: 'groups_join',
          message: subService.limitReachedMessage('groups_join'),
        );
      }
      return;
    }

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

    // Borough gate: block cross-borough group joins with user feedback
    if (!BoroughUiHelpers.canAct(
      feature: HuddlFeature.groups,
      targetBorough: group.creatorBorough,
    )) {
      if (mounted) {
        BoroughUiHelpers.showBlockedSnackBar(
          context,
          featureLabel: 'Groups',
          targetBorough: group.creatorBorough,
        );
      }
      return;
    }

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
      privacy: GroupPrivacy.public,
      targetAudience: group.targetAudience,
      creatorBorough: group.creatorBorough,
      creatorId: group.creatorId,
      creatorName: group.creatorName,
    );

    await _invitationService.joinPublicGroup(groupObj, userName);

    // Record usage for subscription tracking
    subService.recordGroupJoin();

    // CRITICAL FIX: Force UI refresh by updating state AND notifying listeners
    if (mounted) {
      setState(() {});
      // Trigger Messages tab refresh to show newly joined group
      widget.groupsChangedNotifier.value++;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Joined ${group.name}! Go to Messages tab to start chatting.',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: HuddlColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ── Audience filter labels for "Show groups for" ──────────────────────
  static const List<String> _audienceLabels = [
    'Aspiring parents',
    'Parents expecting a baby',
    'Mums',
    'Dads',
  ];

  // ── Filter and sort bottom sheet ──────────────────────────────────────
  void _showFilterSortSheet() {
    Set<String> tempAudiences = Set<String>.from(_selectedAudiences);
    String tempSort = _selectedSort;
    bool tempSmartSort = _aiRecommendationsEnabled;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // ── helper: non-Recommended sort options ─────────────────
            const otherSorts = ['Most Members', 'Newest', 'A-Z'];

            return Container(
              decoration: BoxDecoration(
                color: context.hc.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              // Let sheet grow with content but cap at 92% of screen
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.92,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── drag handle ──────────────────────────────────────
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // ── Header: X | "Filter and sort" | RESET ──
                          Row(
                            children: [
                              Semantics(
                                label: 'Close filter sheet',
                                button: true,
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(ctx);
                                  },
                                  child: SizedBox(
                                    width: 48, height: 48,
                                    child: Icon(Icons.close, size: 24,
                                        color: context.hc.textPrimary),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text('Filter and sort',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18, fontWeight: FontWeight.w700,
                                      color: context.hc.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Semantics(
                                label: 'Reset all filters',
                                button: true,
                                child: GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setSheetState(() {
                                      tempAudiences = {};
                                      tempSort = 'Recommended';
                                      tempSmartSort = true;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text('RESET',
                                      style: _adaptiveText(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── "Show groups for" checkboxes ─────────────
                          Text('Show groups for',
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._audienceLabels.map((label) {
                            final isChecked = tempAudiences.contains(label);
                            return Semantics(
                              label: isChecked
                                  ? '$label filter selected'
                                  : '$label filter',
                              toggled: isChecked,
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setSheetState(() {
                                    if (isChecked) {
                                      tempAudiences.remove(label);
                                    } else {
                                      tempAudiences.add(label);
                                    }
                                  });
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 48),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 26, height: 26,
                                        decoration: BoxDecoration(
                                          color: isChecked
                                              ? HuddlColors.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isChecked
                                                ? HuddlColors.primary
                                                : HuddlColors.gray300,
                                            width: 2,
                                          ),
                                        ),
                                        child: isChecked
                                            ? const Icon(Icons.check,
                                                size: 18, color: HuddlColors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 14),
                                      Text(label,
                                        style: _adaptiveText(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w400,
                                          color: context.hc.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 24),

                          // ╔══════════════════════════════════════════════╗
                          // ║  SORT BY                                     ║
                          // ╚══════════════════════════════════════════════╝
                          Text('Sort by',
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── ① Smart Sort card (Recommended) ─────────
                          _buildSmartSortCard(
                            isSelected: tempSort == 'Recommended',
                            smartEnabled: tempSmartSort,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setSheetState(() => tempSort = 'Recommended');
                            },
                            onToggle: (val) {
                              HapticFeedback.selectionClick();
                              setSheetState(() {
                                tempSmartSort = val;
                                // selecting the card when enabling smart sort
                                if (val) tempSort = 'Recommended';
                              });
                            },
                          ),
                          const SizedBox(height: 6),

                          // ── ② Other sort options ─────────────────────
                          ...otherSorts.map((option) {
                            final isActive = tempSort == option;
                            return Semantics(
                              label: isActive
                                  ? '$option sort selected'
                                  : 'Sort by $option',
                              selected: isActive,
                              child: GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setSheetState(() => tempSort = option);
                                },
                                child: Container(
                                  width: double.infinity,
                                  constraints:
                                      const BoxConstraints(minHeight: 48),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? HuddlColors.primary
                                            .withValues(alpha: 0.07)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isActive
                                          ? HuddlColors.primary
                                              .withValues(alpha: 0.25)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_sortIcon(option),
                                        size: 18,
                                        color: isActive
                                            ? HuddlColors.primary
                                            : HuddlColors.textHint,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(option,
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
                                            size: 20,
                                            color: HuddlColors.primary),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // ── Apply button (sticky at bottom) ──────────────────
                  Container(
                    color: context.hc.surface,
                    padding: EdgeInsets.fromLTRB(
                        20, 10, 20,
                        MediaQuery.of(ctx).padding.bottom + 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedAudiences = tempAudiences;
                            _selectedSort = tempSort;
                            _aiRecommendationsEnabled = tempSmartSort;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text('Apply',
                          style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
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

  // ── Smart Sort card widget ────────────────────────────────────────────────
  Widget _buildSmartSortCard({
    required bool isSelected,
    required bool smartEnabled,
    required VoidCallback onTap,
    required ValueChanged<bool> onToggle,
  }) {
    // Compute a live score preview for the current user's profile
    final sampleScore = _discoverAi.getGroupRecommendationScore(
      {'id': 'sample', 'category': 'PARENTING', 'memberCount': 500,
       'creatorBorough': _userBorough, 'targetAudience': <String>[]},
      userBorough: _userBorough,
      parentType: _userParentType,
      stagesOfLife: _userStagesOfLife,
    );
    final scoreFactors = _buildScoreFactors();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    HuddlColors.primary.withValues(alpha: 0.12),
                    HuddlColors.blueUI.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : HuddlColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? HuddlColors.primary.withValues(alpha: 0.45)
                : HuddlColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: icon + title + AI badge + checkmark ──────────
            Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? HuddlColors.primary
                        : HuddlColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_awesome_rounded,
                    size: 18,
                    color: isSelected ? Colors.white : HuddlColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Smart Sort',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? HuddlColors.primary
                                  : HuddlColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // AI badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [HuddlColors.blueUI, HuddlColors.primary],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('AI',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text('Personalised to your profile',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle,
                      size: 22, color: HuddlColors.primary),
              ],
            ),

            const SizedBox(height: 12),

            // ── Row 2: score factor pills ────────────────────────────
            if (scoreFactors.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: scoreFactors.map((f) => _scoreFactorPill(f)).toList(),
              ),

            if (scoreFactors.isNotEmpty) const SizedBox(height: 12),

            // ── Row 3: "What's this?" description ────────────────────
            Text(
              'Groups are ranked by how well they match your profile — '
              'borough, parenting stage, interests, and activity.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: HuddlColors.textSecondary,
                height: 1.45,
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Row 4: Smart Sort on/off toggle ─────────────────────
            Row(
              children: [
                Icon(
                  smartEnabled
                      ? Icons.psychology_rounded
                      : Icons.psychology_alt_outlined,
                  size: 16,
                  color: smartEnabled
                      ? HuddlColors.primary
                      : HuddlColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    smartEnabled
                        ? 'AI ranking active'
                        : 'AI ranking off — showing default order',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: smartEnabled
                          ? HuddlColors.primary
                          : HuddlColors.textTertiary,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.82,
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: smartEnabled,
                    activeThumbColor: HuddlColors.primary,
                    activeTrackColor: HuddlColors.primary.withValues(alpha: 0.35),
                    onChanged: onToggle,
                  ),
                ),
              ],
            ),

            // ── Row 5: score bar (only when AI is on) ───────────────
            if (smartEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Match quality',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (sampleScore / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            HuddlColors.primary.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            HuddlColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${sampleScore.round()}%',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Returns a short list of scoring factors active for the current user.
  List<String> _buildScoreFactors() {
    final factors = <String>[];
    if (_userBorough != null && _userBorough!.isNotEmpty &&
        _userBorough != 'Unknown Borough') {
      factors.add('📍 ${_userBorough!}');
    }
    if (_userParentType == 'mum') {
      factors.add('👩 Mums');
    } else if (_userParentType == 'dad') {
      factors.add('👨 Dads');
    }
    if (_userStagesOfLife.contains('expecting')) {
      factors.add('🤰 Expecting');
    }
    if (_userStagesOfLife.contains('new_parent')) {
      factors.add('👶 New parent');
    }
    factors.add('⭐ Popularity');
    return factors;
  }

  Widget _scoreFactorPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HuddlColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: HuddlColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Text(label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: HuddlColors.primary,
        ),
      ),
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
        return Icons.explore;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _filteredGroups;
    final bool hasActiveFilters = _selectedAudiences.isNotEmpty || _selectedSort != 'Recommended';
    final contextLine = _discoverAi.getContextExplanation(
      userBorough: _userBorough,
      parentType: _userParentType,
    );

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── Error banner ─────────────────────────────────────────
            if (_hasLoadError)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: HuddlColors.warningBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HuddlColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: HuddlColors.warningDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Could not load your profile. Showing all groups.',
                          style: _adaptiveText(fontSize: 11, color: HuddlColors.warningDark)),
                      ),
                      Semantics(
                        label: 'Retry loading profile',
                        button: true,
                        child: GestureDetector(
                          onTap: _loadUserProfile,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Retry', style: _adaptiveText(
                              fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.primary,
                            )),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Filter and sort pill (hidden when search is active) ────
            if (!_isSearchActive)
              SliverToBoxAdapter(
                child: Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Semantics(
                        label: hasActiveFilters ? 'Active filters. Tap to change.' : 'Filter and sort groups',
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showFilterSortSheet();
                          },
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 18,
                                  color: hasActiveFilters
                                      ? HuddlColors.primary
                                      : context.hc.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  hasActiveFilters && _selectedAudiences.isNotEmpty
                                      ? 'Filter and sort (${_selectedAudiences.length})'
                                      : hasActiveFilters
                                          ? 'Filter and sort · $_selectedSort'
                                          : 'Filter and sort',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: hasActiveFilters
                                        ? HuddlColors.primary
                                        : context.hc.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),

            // ── Search active: inline search field row ─────────────────
            if (_isSearchActive)
              SliverToBoxAdapter(
                child: Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.hc.inputBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 12, right: 6),
                                child: Icon(Icons.search, size: 18,
                                    color: HuddlColors.primary),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  textAlignVertical: TextAlignVertical.center,
                                  onChanged: (val) {
                                    _discoverAi.recordSearch(val);
                                    setState(() {
                                      _searchQuery = val;
                                      if (val.isNotEmpty) {
                                        _aiSuggestions = _discoverAi.getPredictiveSuggestions(
                                          partialQuery: val,
                                          userBorough: _userBorough,
                                          stagesOfLife: _userStagesOfLife,
                                          parentType: _userParentType,
                                        );
                                      }
                                    });
                                  },
                                  style: _adaptiveText(
                                      fontSize: 14, color: context.hc.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'Search groups',
                                    hintStyle: _adaptiveText(
                                        fontSize: 14, color: context.hc.textTertiary),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.only(bottom: 2),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Icon(Icons.close, size: 16,
                                        color: context.hc.textTertiary),
                                  ),
                                )
                              else
                                const SizedBox(width: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── AI predictive suggestions (shown while typing) ────────
            if (_searchQuery.isNotEmpty && _aiSuggestions.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _aiSuggestions.take(3).map((s) {
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _searchQuery = s.query;
                            _searchController.text = s.query;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: HuddlColors.teal.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, size: 11, color: HuddlColors.teal),
                              const SizedBox(width: 4),
                              Text(s.query, style: _adaptiveText(
                                fontSize: 11, fontWeight: FontWeight.w500,
                                color: HuddlColors.teal,
                              )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),



            // ── AI Context Banner (transparency) ─────────────────────
            if (!_isSearchActive && _aiRecommendationsEnabled && _showAiContextBanner)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Semantics(
                    label: contextLine,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: HuddlColors.teal.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 12, color: HuddlColors.teal),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(contextLine,
                              style: _adaptiveText(fontSize: 11, color: HuddlColors.teal)),
                          ),
                          // Dismiss banner
                          Semantics(
                            label: 'Dismiss personalisation banner',
                            button: true,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() => _showAiContextBanner = false);
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: HuddlColors.teal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // CTA Card removed — circular FAB below is the sole "Create group" action

            // ── "Suggested for you" header — default view only ────────
            if (!_isSearchActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suggested for you',
                        style: _adaptiveText(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Search active: section label ──────────────────────────
            if (_isSearchActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'SUGGESTED GROUPS',
                    style: _adaptiveText(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textTertiary,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),

            // ── Group list — compact rows when searching, cards otherwise ──
            if (groups.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final group = groups[index];
                    final isJoined = _invitationService.isGroupJoined(group.id) ||
                        group.creatorId == 'current_user';
                    final canAccess = _canAccessGroup(group);

                    if (_isSearchActive) {
                      // ── Compact search result row (Figma style) ────────────
                      return GestureDetector(
                        onTap: () {
                          _discoverAi.recordGroupView(group.id, group.category);
                          if (!canAccess) {
                            _showGroupAccessDeniedDialog(context, group);
                            return;
                          }
                          Navigator.pushNamed(context, '/group_details',
                              arguments: {
                                'groupId': group.id,
                                'groupName': group.name,
                                'groupImageUrl': group.imageUrl,
                                'groupDescription': group.description,
                                'memberCount': group.memberCount,
                                'isPrivate': group.isPrivate,
                                'creatorId': group.creatorId,
                                'creatorBorough': group.creatorBorough,
                                'isJoined': isJoined,
                              });
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          color: context.hc.surface,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              // Thumbnail — 56×56 rounded rect
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: group.imageUrl.isNotEmpty
                                    ? Image.network(
                                        group.imageUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _SearchResultPlaceholder(
                                                name: group.name),
                                      )
                                    : _SearchResultPlaceholder(
                                        name: group.name),
                              ),
                              const SizedBox(width: 12),
                              // Text block
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Category label — uppercase light grey
                                    Text(
                                      group.targetAudience.join(', ').toUpperCase(),
                                      style: _adaptiveText(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: context.hc.textTertiary,
                                        letterSpacing: 0.4,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    // Group name — bold dark
                                    Text(
                                      group.name,
                                      style: _adaptiveText(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: context.hc.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    // Member count
                                    Text(
                                      '${group.memberCount} members',
                                      style: _adaptiveText(
                                        fontSize: 12,
                                        color: context.hc.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Join button — light grey pill
                              if (!isJoined)
                                GestureDetector(
                                  onTap: () {
                                    if (!canAccess) {
                                      _showGroupAccessDeniedDialog(
                                          context, group);
                                      return;
                                    }
                                    _onJoinTap(group.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F2F2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Join',
                                      style: _adaptiveText(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: context.hc.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }

                    // ── Full card (default view) ────────────────────────────
                    final aiSummary = _discoverAi.summarizeGroup(
                      group.toJson(),
                      parentType: _userParentType,
                      stagesOfLife: _userStagesOfLife,
                      userBorough: _userBorough,
                    );
                    final existingFeedback = _discoverAi.getFeedback(group.id);

                    return _DiscoverGroupCard(
                      group: group,
                      isJoined: isJoined,
                      canAccess: canAccess,
                      aiSummary: aiSummary,
                      aiFeedback: existingFeedback,
                      showAiBadges: _aiRecommendationsEnabled,
                      onJoinTap: () {
                        if (!canAccess) {
                          _showGroupAccessDeniedDialog(context, group);
                          return;
                        }
                        _onJoinTap(group.id);
                      },
                      onTap: () {
                        _discoverAi.recordGroupView(group.id, group.category);
                        if (!canAccess) {
                          _showGroupAccessDeniedDialog(context, group);
                          return;
                        }
                        Navigator.pushNamed(context, '/group_details',
                            arguments: {
                              'groupId': group.id,
                              'groupName': group.name,
                              'groupImageUrl': group.imageUrl,
                              'groupDescription': group.description,
                              'memberCount': group.memberCount,
                              'isPrivate': group.isPrivate,
                              'creatorId': group.creatorId,
                              'creatorBorough': group.creatorBorough,
                              'isJoined': isJoined,
                            });
                      },
                      onFeedback: (isPositive) {
                        HapticFeedback.selectionClick();
                        _discoverAi.submitFeedback(
                          group.id, isPositive,
                          category: group.category,
                        );
                        setState(() {});
                      },
                    );
                  },
                  childCount: groups.length,
                ),
              ),

            // ── Empty state ──────────────────────────────────────────
            if (groups.isEmpty)
              SliverToBoxAdapter(
                child: HuddlEmptyState(
                  illustration: HuddlIllustration.community,
                  illustrationHeight: 180,
                  title: hasActiveFilters
                      ? 'No groups match your search'
                      : 'No groups in your area yet',
                  subtitle: hasActiveFilters
                      ? 'Try adjusting your filters or search terms.'
                      : 'Be the first to create a group\nfor parents in your borough!',
                  actionLabel: hasActiveFilters ? 'Clear filters' : null,
                  onAction: hasActiveFilters
                      ? () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedAudiences = {};
                            _selectedSort = 'Recommended';
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        }
                      : null,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),

        // FAB removed — now handled by the parent Scaffold in events_screen.dart


      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DISCOVER GROUP CARD
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, Map<String, dynamic>> _discoverCardStyles = {
  // General / Popular
  'disc_first_time_mums':     {'icon': Icons.child_friendly,      'color': HuddlColors.primary},
  'disc_dads_connect':        {'icon': Icons.man,                  'color': HuddlColors.teal},
  'disc_bump_to_baby':        {'icon': Icons.pregnant_woman,       'color': HuddlColors.primaryLight},
  'disc_pregnancy_antenatal': {'icon': Icons.favorite,             'color': HuddlColors.accentCoral},
  'disc_newborn_club':        {'icon': Icons.baby_changing_station,'color': HuddlColors.primary},
  'disc_single_parents':      {'icon': Icons.person,               'color': HuddlColors.teal},
  'disc_lgbtq_parents':       {'icon': Icons.diversity_3,          'color': HuddlColors.accentAmber},
  'disc_adoption_fostering':  {'icon': Icons.family_restroom,      'color': HuddlColors.teal},
  // Language & Culture
  'disc_dutch_parents':       {'icon': Icons.language,             'color': HuddlColors.teal},
  'disc_german_parents':      {'icon': Icons.language,             'color': HuddlColors.accentAmber},
  // Sleep & Feeding
  'disc_baby_sleep':          {'icon': Icons.bedtime,              'color': HuddlColors.yellowMedium},
  'disc_breastfeeding':       {'icon': Icons.child_care,           'color': HuddlColors.primary},
  'disc_weaning_first_foods': {'icon': Icons.restaurant,           'color': HuddlColors.accentAmber},
  'disc_child_nutrition':     {'icon': Icons.lunch_dining,         'color': HuddlColors.accentAmber},
  'disc_healthy_meals':       {'icon': Icons.restaurant,           'color': HuddlColors.accentAmber},
  'disc_allergies_dietary':   {'icon': Icons.no_food,              'color': HuddlColors.error},
  // Education & Learning
  'disc_montessori_parenting':{'icon': Icons.school,               'color': HuddlColors.teal},
  'disc_forest_school':       {'icon': Icons.park,                 'color': HuddlColors.teal},
  'disc_home_education':      {'icon': Icons.home,                 'color': HuddlColors.accentAmber},
  'disc_baby_sign_language':  {'icon': Icons.sign_language,        'color': HuddlColors.teal},
  // Activities & Play
  'disc_baby_sensory':        {'icon': Icons.toys,                 'color': HuddlColors.primary},
  'disc_toddler_activities':  {'icon': Icons.directions_run,       'color': HuddlColors.accentCoral},
  'disc_cambridge_playgrounds':{'icon': Icons.outdoor_grill,       'color': HuddlColors.teal},
  // Fitness & Sport
  'disc_buggy_runners':       {'icon': Icons.directions_run,       'color': HuddlColors.accentCoral},
  'disc_postnatal_fitness':   {'icon': Icons.fitness_center,       'color': HuddlColors.accentCoral},
  'disc_postnatal_yoga':      {'icon': Icons.self_improvement,     'color': HuddlColors.primary},
  'disc_buggy_bootcamp':      {'icon': Icons.sports,               'color': HuddlColors.accentCoral},
  'disc_cambridge_tennis':    {'icon': Icons.sports_tennis,        'color': HuddlColors.teal},
  'disc_cambridge_sports':    {'icon': Icons.sports_soccer,        'color': HuddlColors.teal},
  // Wellbeing & Support
  'disc_mental_health':       {'icon': Icons.spa,                  'color': HuddlColors.primaryLight},
  'disc_nct_cambridge':       {'icon': Icons.group,                'color': HuddlColors.primary},
  'disc_special_needs_send':  {'icon': Icons.accessibility_new,    'color': HuddlColors.teal},
  'disc_parents_multiples':   {'icon': Icons.people,               'color': HuddlColors.accentAmber},
  'disc_dad_baby':            {'icon': Icons.man,                  'color': HuddlColors.teal},
  // Childcare & Practicalities
  'disc_nanny_share':         {'icon': Icons.home,                 'color': HuddlColors.yellowMedium},
  'disc_back_to_work':        {'icon': Icons.work,                 'color': HuddlColors.accentAmber},
  'disc_working_parents':     {'icon': Icons.work_outline,         'color': HuddlColors.accentAmber},
  'disc_child_sleep_consultants':{'icon': Icons.nightlight,        'color': HuddlColors.yellowMedium},
  // Lifestyle
  'disc_eco_parenting':       {'icon': Icons.eco,                  'color': HuddlColors.teal},
  'disc_travel_tribe':        {'icon': Icons.flight_takeoff,       'color': HuddlColors.teal},
};

// ── Small placeholder thumbnail for search result rows ────────────────────────
class _SearchResultPlaceholder extends StatelessWidget {
  final String name;
  const _SearchResultPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 56,
      height: 56,
      color: HuddlColors.textTertiary.withValues(alpha: 0.18),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: HuddlColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _DiscoverGroupCard extends StatelessWidget {
  final _GroupItem group;
  final bool isJoined;
  final bool canAccess;
  final VoidCallback onJoinTap;
  final VoidCallback onTap;
  final AiGroupSummary? aiSummary;
  final bool? aiFeedback; // null = no feedback, true = liked, false = disliked
  final bool showAiBadges;
  final void Function(bool isPositive)? onFeedback;

  const _DiscoverGroupCard({
    required this.group,
    required this.isJoined,
    this.canAccess = true,
    required this.onJoinTap,
    required this.onTap,
    this.aiSummary,
    this.aiFeedback,
    this.showAiBadges = false,
    this.onFeedback,
  });

  /// Privacy tag label: 'Public', 'Private', or the parent group name
  String get _privacyTagLabel {
    switch (group.privacy) {
      case GroupPrivacy.public:
        return 'Public';
      case GroupPrivacy.group:
        return group.parentGroupName ?? 'Group';
      case GroupPrivacy.private_:
        return 'Private';
    }
  }



  @override
  Widget build(BuildContext context) {
    final style = _discoverCardStyles[group.id] ??
        {'icon': Icons.people, 'color': HuddlColors.primary};
    final Color catColor = style['color'] as Color;
    final IconData catIcon = style['icon'] as IconData;

    return Semantics(
      label: '${group.name}, ${group.memberCount} members, $_privacyTagLabel group',
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Clean cover image (no overlay tags) ─────────────────
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: _buildCoverImage(
                  imageUrl: group.imageUrl,
                  fallbackIcon: catIcon,
                  fallbackColor: catColor,
                ),
              ),
            ),
            // ── Card body: Figma-style — category + name + members + Join ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label (small uppercase, grey)
                  Text(
                    group.targetAudience.isNotEmpty
                        ? group.targetAudience.join(', ').toUpperCase()
                        : _privacyTagLabel.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textTertiary,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Group name — bold, dark
                  Text(
                    group.name,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // AI-generated one-line tagline (shown when available)
                  if (group.aiTagline != null && group.aiTagline!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      group.aiTagline!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: context.hc.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Bottom row: member avatar photos + count + Join button
                  Row(
                    children: [
                      // Overlapping real-photo avatar circles (3 fixed)
                      SizedBox(
                        width: 62,
                        height: 24,
                        child: Stack(
                          children: [
                            for (int i = 0; i < 3; i++)
                              Positioned(
                                left: i * 18.0,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                  child: ClipOval(
                                    child: Image.network(
                                      _kMemberAvatars[
                                          (group.id.hashCode + i) %
                                              _kMemberAvatars.length],
                                      width: 24,
                                      height: 24,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                        color: catColor
                                            .withValues(alpha: 0.25),
                                        child: Icon(Icons.person,
                                            size: 12, color: catColor),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${group.memberCount} members',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ),
                      // Join / Joined / Restricted button — grey pill (Figma)
                      Semantics(
                        label: isJoined ? 'Already joined ${group.name}' : (!canAccess ? 'Restricted group' : 'Join ${group.name}'),
                        button: !isJoined,
                        child: GestureDetector(
                          onTap: isJoined ? null : () {
                            HapticFeedback.lightImpact();
                            onJoinTap();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: isJoined
                                  ? const Color(0xFFF0F0F0)
                                  : (!canAccess
                                      ? const Color(0xFFF0F0F0)
                                      : const Color(0xFFF2F2F2)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isJoined ? 'Joined' : (!canAccess ? 'Restricted' : 'Join'),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isJoined
                                    ? HuddlColors.textTertiary
                                    : (!canAccess
                                        ? HuddlColors.textHint
                                        : context.hc.textPrimary),
                              ),
                            ),
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
      ),
      ),
    );
  }

  /// Builds the cover image from various sources: asset, http URL, base64,
  /// or falls back to a coloured icon container.
  Widget _buildCoverImage({
    required String imageUrl,
    required IconData fallbackIcon,
    required Color fallbackColor,
  }) {
    Widget fallback() => Container(
          color: fallbackColor.withValues(alpha: 0.12),
          child: Center(
            child: Icon(fallbackIcon, size: 40, color: fallbackColor),
          ),
        );

    Widget placeholder() => Container(
          color: fallbackColor.withValues(alpha: 0.12),
          child: Center(
            child: Icon(fallbackIcon, size: 40,
                color: fallbackColor.withValues(alpha: 0.4)),
          ),
        );

    if (imageUrl.isEmpty) return fallback();

    if (imageUrl.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(imageUrl);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => fallback(),
          );
        }
      } catch (_) {}
      return fallback();
    }

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        placeholder: (_, __) => placeholder(),
        errorWidget: (_, __, ___) => fallback(),
      );
    }

    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return fallback();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC WRAPPER — Exposes the Discover/Groups functionality for use in other
// screens (e.g. the Discover screen's "Groups" tab).
// ═══════════════════════════════════════════════════════════════════════════════

class DiscoverGroupsTab extends StatefulWidget {
  /// Set to `true` to activate inline search mode.
  final ValueNotifier<bool>? searchTrigger;
  /// Set to `true` to close/reset search mode (e.g. when leaving the tab).
  final ValueNotifier<bool>? resetTrigger;
  const DiscoverGroupsTab({super.key, this.searchTrigger, this.resetTrigger});

  @override
  State<DiscoverGroupsTab> createState() => _DiscoverGroupsTabState();
}

class _DiscoverGroupsTabState extends State<DiscoverGroupsTab> {
  final ValueNotifier<int> _groupsChangedNotifier = ValueNotifier<int>(0);
  final GlobalKey<_DiscoverTabState> _discoverKey = GlobalKey<_DiscoverTabState>();

  @override
  void initState() {
    super.initState();
    widget.searchTrigger?.addListener(_onSearchTrigger);
    widget.resetTrigger?.addListener(_onResetTrigger);
  }

  @override
  void didUpdateWidget(DiscoverGroupsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTrigger != widget.searchTrigger) {
      oldWidget.searchTrigger?.removeListener(_onSearchTrigger);
      widget.searchTrigger?.addListener(_onSearchTrigger);
    }
    if (oldWidget.resetTrigger != widget.resetTrigger) {
      oldWidget.resetTrigger?.removeListener(_onResetTrigger);
      widget.resetTrigger?.addListener(_onResetTrigger);
    }
  }

  void _onSearchTrigger() {
    if (widget.searchTrigger?.value == true) {
      _discoverKey.currentState?.activateSearch();
      widget.searchTrigger?.value = false;
    }
  }

  void _onResetTrigger() {
    if (widget.resetTrigger?.value == true) {
      _discoverKey.currentState?.deactivateSearch();
      widget.resetTrigger?.value = false;
    }
  }

  @override
  void dispose() {
    widget.searchTrigger?.removeListener(_onSearchTrigger);
    widget.resetTrigger?.removeListener(_onResetTrigger);
    _groupsChangedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DiscoverTab(
      key: _discoverKey,
      groupsChangedNotifier: _groupsChangedNotifier,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAVED TAB
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified wrapper for displaying both SavedMessage and SavedThread in the Saved tab.
class _SavedItem {
  final SavedMessage? message;
  final SavedThread? thread;
  final SavedEvent? event;

  _SavedItem.fromMessage(this.message)
      : thread = null,
        event = null;
  _SavedItem.fromThread(this.thread)
      : message = null,
        event = null;
  _SavedItem.fromEvent(this.event)
      : message = null,
        thread = null;

  bool get isThread => thread != null;
  bool get isEvent => event != null;
  String get id => isThread
      ? thread!.id
      : isEvent
          ? event!.id
          : message!.id;
  DateTime get savedAt => isThread
      ? thread!.savedAt
      : isEvent
          ? event!.savedAt
          : message!.savedAt;
}

class _SavedTab extends StatefulWidget {
  final ValueNotifier<String> searchNotifier;
  const _SavedTab({required this.searchNotifier});

  @override
  State<_SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<_SavedTab> {
  final SavedMessageService _savedMessageService = SavedMessageService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Defer listener registration and data load to avoid setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _savedMessageService.addListener(_onUpdate);
      widget.searchNotifier.addListener(_onSearchChanged);
      _init();
    });
  }

  @override
  void dispose() {
    _savedMessageService.removeListener(_onUpdate);
    widget.searchNotifier.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await _savedMessageService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  /// Build a unified list of saved messages + saved threads + saved events,
  /// sorted newest first.
  List<_SavedItem> _filteredSaved() {
    final q = widget.searchNotifier.value.toLowerCase();
    final items = <_SavedItem>[];

    // Add saved events (bookmarks) — shown first by default as they tend
    // to be time-sensitive
    for (final ev in _savedMessageService.savedEvents) {
      if (q.isEmpty ||
          ev.title.toLowerCase().contains(q) ||
          ev.location.toLowerCase().contains(q) ||
          ev.organiser.toLowerCase().contains(q) ||
          ev.date.toLowerCase().contains(q)) {
        items.add(_SavedItem.fromEvent(ev));
      }
    }

    // Add saved messages
    for (final m in _savedMessageService.savedMessages) {
      if (q.isEmpty ||
          m.message.toLowerCase().contains(q) ||
          m.senderName.toLowerCase().contains(q) ||
          m.sourceName.toLowerCase().contains(q)) {
        items.add(_SavedItem.fromMessage(m));
      }
    }

    // Add saved threads
    for (final t in _savedMessageService.savedThreads) {
      if (q.isEmpty ||
          t.topicName.toLowerCase().contains(q) ||
          t.rootMessageText.toLowerCase().contains(q) ||
          t.rootSenderName.toLowerCase().contains(q) ||
          t.groupName.toLowerCase().contains(q)) {
        items.add(_SavedItem.fromThread(t));
      }
    }

    // Sort by savedAt descending (newest first)
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  /// Show delete confirmation dialog matching the Messages tab pattern.
  void _confirmDeleteSavedMessage(SavedMessage msg) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to permanently delete this saved message?',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textPrimary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
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
                          color: context.hc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _savedMessageService.unsaveMessage(msg.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Saved message deleted'),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: HuddlColors.primary),
      );
    }

    final allMessages = _savedMessageService.savedMessages;
    final allThreads = _savedMessageService.savedThreads;
    // allEvents used below in empty-state check

    final allEvents = _savedMessageService.savedEvents;

    // No saved items at all — show empty state (no search bar needed)
    if (allMessages.isEmpty && allThreads.isEmpty && allEvents.isEmpty) {
      return HuddlEmptyState(
        illustration: HuddlIllustration.saved,
        title: 'No saved items yet',
        subtitle: 'Bookmark events to save them here,\nor long-press a message to save it.',
      );
    }

    final filtered = _filteredSaved();

    return Column(
      children: [
        // ── Results list ───────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: context.hc.textTertiary),
                      const SizedBox(height: 12),
                      Text(
                        'No results for "${widget.searchNotifier.value}"',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: context.hc.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Try a different keyword',
                        style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    Widget card;
                    VoidCallback onDelete;
                    if (item.isThread) {
                      card = _SavedThreadCard(
                        savedThread: item.thread!,
                        onTap: () => _navigateToThread(item.thread!),
                      );
                      onDelete = () => _confirmDeleteSavedThread(item.thread!);
                    } else if (item.isEvent) {
                      card = _SavedEventCard(
                        savedEvent: item.event!,
                        onTap: () => _navigateToEvent(item.event!),
                      );
                      onDelete = () => _removeSavedEvent(item.event!);
                    } else {
                      card = _SavedMessageCard(
                        savedMessage: item.message!,
                        onTap: () => _navigateToSource(item.message!),
                      );
                      onDelete = () => _confirmDeleteSavedMessage(item.message!);
                    }
                    return Column(
                      children: [
                        _SwipeActionRow(
                          key: ValueKey('saved_swipe_${item.id}'),
                          isUnread: false,
                          onDelete: onDelete,
                          onToggleRead: () {},
                          child: card,
                        ),
                        if (index < filtered.length - 1)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: context.hc.divider,
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Navigate to the event detail screen for a saved event.
  void _navigateToEvent(SavedEvent ev) {
    Navigator.pushNamed(context, '/event_detail', arguments: {
      'id': ev.eventId,
      'title': ev.title,
      'date': ev.date,
      'time': ev.time,
      'location': ev.location,
      'organiser': ev.organiser,
      'imageUrl': ev.imageUrl,
      'isFree': ev.isFree,
      'price': ev.price,
      'category': ev.category,
      'isOnline': ev.isOnline,
      'description': '',
      'attendees': 0,
      'isUserCreated': false,
    });
  }

  /// Remove a bookmarked event without a confirmation dialog
  /// (mirrors the swipe-to-delete UX used for saved messages).
  Future<void> _removeSavedEvent(SavedEvent ev) async {
    await _savedMessageService.unsaveEvent(ev.eventId);
    // Also remove from EventService in-memory cache so the bookmark icon updates
    final eventService = EventService();
    eventService.clearBookmarkCache(ev.eventId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Event bookmark removed'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
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

  /// Navigate to the group chat and auto-open the thread panel for the saved thread.
  void _navigateToThread(SavedThread thread) {
    Navigator.pushNamed(context, '/group_chat', arguments: {
      'groupId': thread.groupId,
      'groupName': thread.groupName,
      'groupImageUrl': thread.groupImageUrl,
      'openThreadForMessageId': thread.rootMessageId,
    });
  }

  /// Confirm deletion of a saved thread.
  void _confirmDeleteSavedThread(SavedThread thread) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to permanently delete this saved thread?',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textPrimary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
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
                          color: context.hc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await _savedMessageService.unsaveThread(thread.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Saved thread deleted'),
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAVED MESSAGE CARD — shows message, source, timestamp, and tap-to-navigate
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedMessageCard extends StatelessWidget {
  final SavedMessage savedMessage;
  final VoidCallback onTap;

  const _SavedMessageCard({
    required this.savedMessage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGroup = savedMessage.isFromGroup;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: context.hc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source info row
            Row(
              children: [
                isGroup
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: HuddlColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.people, size: 14, color: HuddlColors.primary),
                        ),
                      )
                    : MemberAvatar(
                        name: savedMessage.dmRecipientName ?? '?',
                        size: 28,
                        accentColor: _savedColorFromHex(
                            savedMessage.dmRecipientAvatarColor ?? '#FF975C'),
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
                    color: context.hc.textTertiary,
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
                color: context.hc.scaffold,
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
                          color: context.hc.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatMessageTime(savedMessage.timestamp),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    savedMessage.message,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: context.hc.textPrimary,
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
                Icon(Icons.open_in_new, size: 12, color: context.hc.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'Tap to go to ${isGroup ? 'group' : 'conversation'}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: context.hc.textTertiary,
                  ),
                ),
              ],
            ),
          ],
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
// SAVED THREAD CARD — shows thread topic, root message, reply count, and tap hint
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedThreadCard extends StatelessWidget {
  final SavedThread savedThread;
  final VoidCallback onTap;

  const _SavedThreadCard({
    required this.savedThread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: context.hc.surface,
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
                    color: HuddlColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.topic, size: 14, color: HuddlColors.teal),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.forum, size: 12, color: HuddlColors.teal),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              savedThread.topicName,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: HuddlColors.teal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        savedThread.replies.isEmpty
                            ? 'Message from ${savedThread.groupName}'
                            : 'Thread from ${savedThread.groupName}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: context.hc.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatSavedTime(savedThread.savedAt),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: context.hc.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Root message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.hc.scaffold,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(color: HuddlColors.teal, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        savedThread.rootSenderName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatMessageTime(savedThread.rootTimestamp),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    savedThread.rootMessageText,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: context.hc.textPrimary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Reply count badge (only shown when there are replies/merged messages)
                  if (savedThread.replies.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.reply, size: 14, color: HuddlColors.teal),
                      const SizedBox(width: 4),
                      Text(
                        '${savedThread.replies.length} ${savedThread.replies.length == 1 ? 'reply' : 'replies'}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Tap hint
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.open_in_new, size: 12, color: context.hc.textTertiary),
                const SizedBox(width: 4),
                Text(
                  savedThread.replies.isEmpty
                      ? 'Tap to go to group'
                      : 'Tap to open thread in group',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: context.hc.textTertiary,
                  ),
                ),
              ],
            ),
          ],
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

// ═══════════════════════════════════════════════════════════════════════════════
// SAVED EVENT CARD — shown in Saved tab for bookmarked events
// ═══════════════════════════════════════════════════════════════════════════════

class _SavedEventCard extends StatelessWidget {
  final SavedEvent savedEvent;
  final VoidCallback onTap;

  const _SavedEventCard({
    required this.savedEvent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasImage = savedEvent.imageUrl.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: context.hc.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail / fallback icon
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 62,
                height: 62,
                child: hasImage
                    ? Image.network(
                        savedEvent.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackIcon(context),
                      )
                    : _fallbackIcon(context),
              ),
            ),
            const SizedBox(width: 12),
            // Event details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "Saved event" label
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: HuddlColors.accentAmber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bookmark,
                                size: 11, color: HuddlColors.accentAmber),
                            const SizedBox(width: 4),
                            Text(
                              'Saved Event',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.accentAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Free / price badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: savedEvent.isFree
                              ? HuddlColors.teal.withValues(alpha: 0.12)
                              : HuddlColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          savedEvent.isFree
                              ? 'Free'
                              : (savedEvent.price.isNotEmpty ? savedEvent.price : 'Paid'),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: savedEvent.isFree ? HuddlColors.teal : HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Title
                  Text(
                    savedEvent.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Date & time
                  if (savedEvent.date.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 12, color: context.hc.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            savedEvent.time.isNotEmpty
                                ? '${savedEvent.date} · ${savedEvent.time}'
                                : savedEvent.date,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: context.hc.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 2),
                  // Location / online
                  Row(
                    children: [
                      Icon(
                        savedEvent.isOnline
                            ? Icons.videocam_outlined
                            : Icons.location_on_outlined,
                        size: 12,
                        color: context.hc.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          savedEvent.isOnline ? 'Online event' : savedEvent.location,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Tap hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.open_in_new, size: 11, color: context.hc.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        'Tap to view event',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: context.hc.textTertiary,
                        ),
                      ),
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

  Widget _fallbackIcon(BuildContext context) {
    return Container(
      color: HuddlColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.event, size: 28, color: HuddlColors.primary),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWIPE ACTION ROW — swipe left for Delete (red), right for Mark read/unread (teal)
// ═══════════════════════════════════════════════════════════════════════════════

class _SwipeActionRow extends StatefulWidget {
  final Widget child;
  final bool isUnread;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;
  final String swipeLeftLabel;
  final IconData swipeLeftIcon;

  const _SwipeActionRow({
    super.key,
    required this.child,
    required this.isUnread,
    required this.onDelete,
    required this.onToggleRead,
    this.swipeLeftLabel = 'Delete',
    this.swipeLeftIcon = Icons.delete,
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
          // Swiped left enough — trigger delete/leave
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
          // Background action indicators — clipped to match card border radius
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  children: [
                    // Left side — teal mark read/unread (revealed on right swipe)
                    Expanded(
                      child: Container(
                        color: showRead ? HuddlColors.teal : Colors.transparent,
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
                        color: showDelete ? HuddlColors.error : Colors.transparent,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: AnimatedOpacity(
                          opacity: showDelete ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.swipeLeftIcon, color: Colors.white, size: 22),
                              const SizedBox(height: 2),
                              Text(
                                widget.swipeLeftLabel,
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
      leading: Icon(icon, color: color ?? context.hc.textPrimary),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color ?? context.hc.textPrimary,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEARCH SECTION HEADER — "Chats (3)" or "Messages (12)"
// ═══════════════════════════════════════════════════════════════════════════════

class _SearchSectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SearchSectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.hc.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEEP SEARCH RESULT ROW — shows a matching message within a conversation
// ═══════════════════════════════════════════════════════════════════════════════

class _DeepSearchResultRow extends StatelessWidget {
  final MessageSearchResult result;
  final String query;
  final String Function(DateTime) timeFormat;
  final VoidCallback onTap;

  const _DeepSearchResultRow({
    required this.result,
    required this.query,
    required this.timeFormat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(52, 4, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search icon
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.subdirectory_arrow_right,
                size: 16,
                color: context.hc.textTertiary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name + time
                  Row(
                    children: [
                      Text(
                        result.senderName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeFormat(result.timestamp),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Message text with highlighted query
                  _HighlightedText(
                    text: result.messageText,
                    query: query,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Highlights matching portions of text.
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(
          text: text.substring(start),
          style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
        ));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
          text: text.substring(start, idx),
          style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
        ));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: HuddlColors.primary,
          backgroundColor: HuddlColors.primary.withValues(alpha: 0.1),
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EmptyMessagesState extends StatelessWidget {
  final VoidCallback onSearch;
  const _EmptyMessagesState({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return HuddlEmptyState(
      illustration: HuddlIllustration.chat,
      title: 'No groups yet',
      subtitle: 'Join a group to start chatting\nwith your community.',
      actionLabel: 'Find a group',
      onAction: onSearch,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AI FEEDBACK ROW — thumbs up/down for human-in-the-loop learning
// ═══════════════════════════════════════════════════════════════════════════════

class _AiFeedbackRow extends StatelessWidget {
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;

  const _AiFeedbackRow({
    required this.onThumbsUp,
    required this.onThumbsDown,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onThumbsUp,
          child: Container(
            width: 24, height: 24,
            alignment: Alignment.center,
            child: Icon(Icons.thumb_up_alt_outlined,
                size: 12, color: context.hc.textTertiary.withValues(alpha: 0.5)),
          ),
        ),
        GestureDetector(
          onTap: onThumbsDown,
          child: Container(
            width: 24, height: 24,
            alignment: Alignment.center,
            child: Icon(Icons.thumb_down_alt_outlined,
                size: 12, color: context.hc.textTertiary.withValues(alpha: 0.5)),
          ),
        ),
      ],
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
  final GroupPrivacy privacy;
  bool get isPrivate => privacy == GroupPrivacy.private_;
  final String? parentGroupId;
  final String? parentGroupName;
  final List<String> targetAudience;
  final String? creatorId;
  final String? creatorName;
  final String? creatorBorough;
  final List<String> invitedMemberIds;
  /// AI-generated one-line tagline shown beneath the group name in Discover cards.
  final String? aiTagline;

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
    this.privacy = GroupPrivacy.public,
    this.parentGroupId,
    this.parentGroupName,
    this.targetAudience = const [],
    this.creatorId,
    this.creatorName,
    this.creatorBorough,
    this.invitedMemberIds = const [],
    this.aiTagline,
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
      privacy: g.privacy,
      parentGroupId: g.parentGroupId,
      parentGroupName: g.parentGroupName,
      targetAudience: g.targetAudience,
      creatorId: g.creatorId,
      creatorName: g.creatorName,
      creatorBorough: g.creatorBorough,
      invitedMemberIds: g.invitedMemberIds,
      aiTagline: g.aiTagline,
    );
  }

  bool isVisibleTo(String? parentType, List<String> stagesOfLife) {
    if (targetAudience.isEmpty) return true;
    // Use OR logic: the user must match AT LEAST ONE audience label
    // (e.g. a group for ['Mums', 'Parents expecting a baby'] is visible to
    //  ANY mum OR any expecting parent — not only users who are both)
    for (final label in targetAudience) {
      switch (label) {
        case 'Mums':
          if (parentType == 'mum') return true;
          break;
        case 'Dads':
          if (parentType == 'dad') return true;
          break;
        case 'Parents expecting a baby':
          if (stagesOfLife.contains('expecting')) return true;
          break;
        case 'Aspiring parents':
          if (stagesOfLife.contains('aspiring')) return true;
          break;
      }
    }
    // None of the audience labels matched the current user
    return false;
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
    GroupPrivacy? privacy,
    String? parentGroupId,
    String? parentGroupName,
    List<String>? targetAudience,
    String? creatorId,
    String? creatorName,
    String? creatorBorough,
    List<String>? invitedMemberIds,
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
      privacy: privacy ?? this.privacy,
      parentGroupId: parentGroupId ?? this.parentGroupId,
      parentGroupName: parentGroupName ?? this.parentGroupName,
      targetAudience: targetAudience ?? this.targetAudience,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorBorough: creatorBorough ?? this.creatorBorough,
      invitedMemberIds: invitedMemberIds ?? this.invitedMemberIds,
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
        'privacy': privacy.name,
        'parentGroupId': parentGroupId,
        'parentGroupName': parentGroupName,
        'targetAudience': targetAudience,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'creatorBorough': creatorBorough,
        'invitedMemberIds': invitedMemberIds,
      };
}
