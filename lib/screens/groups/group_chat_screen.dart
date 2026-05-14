import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../models/direct_message.dart';
import '../main_shell.dart';
import '../../services/invitation_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';
import '../../services/media_attach_service.dart';
import '../../services/block_service.dart';
import '../../services/report_service.dart';
import '../../services/message_safety_service.dart';
import '../../services/browser_storage.dart';
import '../../services/default_group_service.dart';
import '../../services/poll_service.dart';
import '../../models/saved_message.dart' show SavedThreadMessage;
import 'create_poll_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/huddl_user_service.dart';
import '../../services/postcode_service.dart';
import '../../services/user_privacy_prefs_service.dart';
import '../../services/firestore_service.dart';
import 'poll_detail_screen.dart';
import 'forward_message_sheet.dart';
import 'thread_reply_screen.dart';
import '../../widgets/document_bubble.dart';
import '../../widgets/emoji_reaction_picker.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/meetup_invite_card.dart';
import '../../widgets/group_invite_card.dart';
import '../../widgets/item_invite_card.dart';
import '../../widgets/event_invite_card.dart';
import '../../widgets/voice_message_bubble.dart';
import '../../services/voice_message_service.dart';
import '../../services/huddl_notification_service.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ── Design tokens — use HuddlColors as single source of truth ────────
const Color _kMyBubble = HuddlColors.peachLight;

class GroupChatScreen extends StatefulWidget {
  /// Fires the groupId string whenever the current user sends any message
  /// (text, media, forwarded card, etc.).  The Messages tab subscribes to
  /// this so it can re-sort the list without a full reload round-trip.
  /// Uses a map-entry {id, counter} so repeated messages in the same group
  /// always trigger the listener even when the groupId hasn't changed.
  static final ValueNotifier<Map<String, dynamic>> messageSent =
      ValueNotifier<Map<String, dynamic>>({'groupId': null, 'seq': 0});

  final String groupId;
  final String groupName;
  final String groupImageUrl;
  final bool isDefaultGroup;
  final bool isPrivate;
  final String? creatorId;
  final String? creatorBorough;
  final List<String> targetAudience;
  final String groupCategory;
  /// When non-null, the chat screen will auto-open the thread panel for this
  /// root message ID immediately after loading.
  final String? openThreadForMessageId;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupImageUrl,
    this.isDefaultGroup = false,
    this.isPrivate = false,
    this.creatorId,
    this.creatorBorough,
    this.targetAudience = const [],
    this.groupCategory = '',
    this.openThreadForMessageId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final InvitationService _invitationService = InvitationService();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final SavedMessageService _savedMessageService = SavedMessageService();
  final BlockService _blockService = BlockService();
  final VoiceMessageService _voiceSvc = VoiceMessageService.instance;
  bool _isVoiceRecording = false;

  /// Whether the user has changed borough and this is an old-borough default group
  bool _canLeaveGroup = false;

  /// Admin state — creator or assigned admins can manage the private group
  bool get _isCreatorOrAdmin =>
      widget.creatorId == 'current_user' || _adminIds.contains('current_user');
  final Set<String> _adminIds = {};

  /// Real members loaded from Firestore for the admin-picker.
  /// Populated by _loadGroupMembers() — starts empty.
  final List<_GroupMember> _groupMembers = [];

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  Timer? _forwardedMsgTimer;
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchMatches = [];
  int _currentMatchIndex = -1;
  // Simulated message status progression for user messages
  final Map<String, MessageStatus> _messageStatuses = {};
  // ── Poll state ──────────────────────────────────────────────────────
  final PollService _pollService = PollService();
  List<ActivePoll> get _polls => _pollService.getPolls(widget.groupId);

  /// Polls pinned by their creator — always shown at the top of chat
  List<ActivePoll> get _pinnedPolls =>
      _polls.where((p) => p.isPinned && !p.isDeleted).toList();

  /// Active polls that are visible in the message flow (not pinned section):
  /// - Not deleted
  /// - Not pinned (pinned ones go to the top pinned section)
  /// - visibleInFlow is true (creator always; non-creator: only before voting
  ///   or if expired so creator can still access their poll)
  List<ActivePoll> get _flowPolls => _polls
      .where((p) =>
          !p.isDeleted &&
          !p.isPinned &&
          (p.visibleInFlow || (p.isExpired && p.isCreatedByMe)))
      .toList();

  /// Count of all non-deleted, non-expired polls (for badge)
  int get _activePollCount =>
      _polls.where((p) => !p.isDeleted && !p.isExpired).length;
  final MediaAttachService _mediaService = MediaAttachService();

  /// Locally added image messages
  final List<_GroupImageMessage> _imageMessages = [];

  /// Locally added document messages
  final List<_GroupDocumentMessage> _documentMessages = [];

  /// Emoji reactions: messageId → { emoji → count }
  final Map<String, Map<String, int>> _reactions = {};

  /// Tracks the current user's own reaction per message (messageId → emoji).
  /// Used by _toggleReaction to remove only this user's previous emoji
  /// without clearing other users' reactions from the local map.
  final Map<String, String> _myReactions = {};

  /// Thread replies: rootMessageId → list of thread replies
  final Map<String, List<ThreadReply>> _threadReplies = {};

  /// Storage key for persisting thread replies per group
  String get _threadStorageKey => 'thread_replies_${widget.groupId}';

  /// Storage keys for persisting unsend states per group
  String get _hiddenMsgKey => 'hidden_msgs_${widget.groupId}';
  String get _deletedEveryoneKey => 'deleted_everyone_${widget.groupId}';

  /// IDs of messages unsent "just for me" (hidden locally)
  final Set<String> _hiddenMessageIds = {};

  /// IDs of messages unsent "for everyone" (shown as "This message was deleted")
  final Set<String> _deletedForEveryoneIds = {};

  /// Firestore real-time message stream subscription
  StreamSubscription<List<Map<String, dynamic>>>? _firestoreMsgSub;

  /// Track Firestore message IDs already shown to avoid duplicates
  final Set<String> _firestoreMsgIds = {};

  /// Live group image URL — starts as widget.groupImageUrl, then resolved
  /// from Firestore if the widget value is blank (e.g. opened via notification).
  late String _liveGroupImageUrl;

  /// Current user's own profile photo URL — resolved once in initState and
  /// reused for every optimistic outgoing message so the sender avatar is
  /// correct immediately (before the Firestore write returns).
  String _myPhotoUrl = '';

  @override
  void initState() {
    super.initState();
    _liveGroupImageUrl = widget.groupImageUrl;
    _loadMessages();
    _blockService.initialize();
    _checkLeaveGroupEligibility();
    _resolveGroupImageIfNeeded();
    _resolveMyPhotoUrl();
    // Periodically reload forwarded messages so cards appear without manual refresh
    _forwardedMsgTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _reloadForwardedMessages();
    });
    // Subscribe to real-time Firestore messages for cross-device chat
    _subscribeToFirestoreMessages();
    // Tell the shell this group chat is now active so foreground FCM banners
    // for this conversation are suppressed (OS heads-up is sufficient).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MainShell.shellKey.currentState?.setActiveGroupChat(widget.groupId);
    });
  }

  /// If the group image URL wasn't passed in (e.g. opened from a notification),
  /// fetch it directly from Firestore using the public getGroup() API.
  Future<void> _resolveGroupImageIfNeeded() async {
    if (_liveGroupImageUrl.isNotEmpty) return; // already have it
    try {
      final group = await FirestoreService().getGroup(widget.groupId);
      final url = group?.imageUrl ?? '';
      if (url.isNotEmpty && mounted) {
        setState(() => _liveGroupImageUrl = url);
      }
    } catch (_) {}
  }

  /// Fetch the current user's own photoUrl once and cache it in [_myPhotoUrl].
  /// Used so that every optimistic outgoing message shows the correct sender
  /// avatar immediately — without waiting for the Firestore write to return.
  Future<void> _resolveMyPhotoUrl() async {
    try {
      final profile = await FirestoreService().getCurrentUserProfile();
      final photo = (profile?['photoUrl'] as String? ?? '').trim();
      if (photo.isNotEmpty && mounted) {
        setState(() => _myPhotoUrl = photo);
      }
    } catch (_) {}
  }

  /// Determine whether the 'Leave group' option should be shown.
  /// Only for default groups when the user has changed their postcode/borough.
  Future<void> _checkLeaveGroupEligibility() async {
    await _onboardingService.initialize();
    if (!widget.isDefaultGroup) {
      // Non-default groups (joined from Discover, user-created, etc.) — can always leave
      setState(() => _canLeaveGroup = true);
      return;
    }
    // Default group — only show leave if user has changed borough
    final hasChanged = _onboardingService.hasChangedBorough;
    if (mounted) {
      setState(() => _canLeaveGroup = hasChanged);
    }
  }

  @override
  void dispose() {
    // Clear active chat so banners resume for other conversations.
    MainShell.shellKey.currentState?.setActiveGroupChat(null);
    _forwardedMsgTimer?.cancel();
    _firestoreMsgSub?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Subscribe to real-time Firestore group messages.
  /// Merges incoming messages from other users into the local list.
  void _subscribeToFirestoreMessages() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    _firestoreMsgSub = FirestoreService()
        .groupMessagesStream(widget.groupId)
        .listen((messages) {
      if (!mounted) return;
      bool added = false;
      for (final m in messages) {
        final id = m['id'] as String? ?? '';
        if (id.isEmpty) continue;

        // ── Always merge reactions — even for already-seen message IDs ────
        // Reaction updates arrive as full doc snapshots; the ID will already
        // be in _firestoreMsgIds but the reactions field may have changed.
        final incomingRxn = m['reactions'];
        if (incomingRxn is Map && incomingRxn.isNotEmpty) {
          final rxnMap = <String, int>{};
          incomingRxn.forEach((k, v) {
            final count = (v as num?)?.toInt() ?? 0;
            if (count > 0) rxnMap[k as String] = count;
          });
          if (rxnMap.isNotEmpty) {
            final current = _reactions[id];
            if (current == null || !_mapsEqual(current, rxnMap)) {
              _reactions[id] = rxnMap;
              added = true; // trigger setState so UI refreshes
            }
          } else {
            if (_reactions.containsKey(id)) {
              _reactions.remove(id);
              added = true;
            }
          }
        }

        // ── Always merge reactionUsers → _myReactions for this device ────
        // This keeps _toggleReaction's per-user replace logic accurate even
        // after the app restarts or the stream delivers an updated snapshot.
        final incomingRxnUsers = m['reactionUsers'];
        if (incomingRxnUsers is Map) {
          final myUid = currentUid ?? '';
          final myEmoji = incomingRxnUsers[myUid] as String?;
          if (myEmoji != null && myEmoji.isNotEmpty) {
            _myReactions[id] = myEmoji;
          } else {
            _myReactions.remove(id);
          }
        }

        // Skip new-message processing for IDs we already have
        if (_firestoreMsgIds.contains(id)) continue;
        final senderId = m['senderId'] as String? ?? '';
        // Skip our own messages — already shown optimistically in _sendMessage()
        if (senderId == currentUid) {
          _firestoreMsgIds.add(id); // track so we don't add again
          continue;
        }
        // Skip messages from blocked users — server-side complement to the
        // UI-level hide already applied in the ListView builder.
        if (senderId.isNotEmpty && _blockService.isUserBlocked(senderId)) {
          _firestoreMsgIds.add(id); // still track so we don't add later
          continue;
        }
        _firestoreMsgIds.add(id);
        final tsRaw = m['timestamp'];
        DateTime ts;
        if (tsRaw is String) {
          ts = DateTime.tryParse(tsRaw) ?? DateTime.now();
        } else if (tsRaw is Timestamp) {
          ts = tsRaw.toDate();
        } else {
          ts = DateTime.now();
        }

        final msgType = m['type'] as String? ?? 'text';

        // ── Image message from another device ──────────────────────────────
        if (msgType == 'image') {
          final imageUrl = m['imageUrl'] as String? ?? '';
          if (imageUrl.isNotEmpty &&
              !_imageMessages.any((img) => img.imageUrl == imageUrl)) {
            _imageMessages.add(_GroupImageMessage(
              imageUrl: imageUrl,
              isMe: false,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
            ));
            added = true;
          }
          continue;
        }

        // ── Location pin from another device ───────────────────────────────
        if (msgType == 'location') {
          final lat = (m['latitude'] as num?)?.toDouble();
          final lng = (m['longitude'] as num?)?.toDouble();
          final locLabel = m['locationLabel'] as String? ?? 'Location';
          // Deduplicate by approximate lat/lng match
          final alreadyHave = _imageMessages.any((img) =>
              img.isLocationPin &&
              img.latitude == lat &&
              img.longitude == lng &&
              img.senderId == senderId);
          if (!alreadyHave) {
            _imageMessages.add(_GroupImageMessage(
              imageUrl: 'location_pin',
              isMe: false,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
              isLocationPin: true,
              latitude: lat,
              longitude: lng,
              locationLabel: locLabel,
            ));
            added = true;
          }
          continue;
        }

        // ── Document from another device ───────────────────────────────────
        if (msgType == 'document') {
          final docName = m['documentName'] as String? ?? 'Document';
          final docSize = (m['documentSize'] as num?)?.toInt();
          final docUrl  = m['documentUrl'] as String? ?? '';
          final alreadyHave = _documentMessages.any((d) =>
              d.senderId == senderId && d.fileName == docName);
          if (!alreadyHave) {
            _documentMessages.add(_GroupDocumentMessage(
              fileName: docName,
              fileSize: docSize,
              fileUrl: docUrl,
              isMe: false,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
            ));
            added = true;
          }
          continue;
        }

        // ── Contact from another device ───────────────────────────────────
        if (msgType == 'contact') {
          final contactMsg = '\u{1F464} Contact: '
              '${m['contactName'] as String? ?? 'Unknown'} - '
              '${m['contactPhone'] as String? ?? ''}';
          if (!_messages.any((e) => e.id == id)) {
            _messages.add(ChatMessage(
              id: id,
              senderId: senderId,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              message: contactMsg,
              timestamp: ts,
              isMe: false,
            ));
            added = true;
          }
          continue;
        }

        // ── Poll from another device ─────────────────────────────────────
        if (msgType == 'poll') {
          final pollQuestion = m['pollQuestion'] as String? ?? '';
          final pollAnnounceId = 'fs_poll_$id';
          if (pollQuestion.isNotEmpty &&
              !_messages.any((e) => e.id == pollAnnounceId)) {
            _messages.add(ChatMessage(
              id: pollAnnounceId,
              senderId: senderId,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              message: '\u{1F4CA} Poll: "$pollQuestion"',
              timestamp: ts,
              isMe: false,
              isSystem: true,
            ));
            added = true;
          }
          // Restore the ActivePoll locally if not already present
          final rawOptions = m['pollOptions'];
          if (rawOptions is List && !_polls.any((p) => p.id == 'fs_$id')) {
            final pollData = PollData(
              question: pollQuestion,
              options: rawOptions.map((e) => e as String).toList(),
              allowMultiple: m['pollAllowMultiple'] as bool? ?? false,
              isCalendarMode: m['pollIsCalendarMode'] as bool? ?? false,
              expiresAt: m['pollExpiresAt'] != null
                  ? DateTime.tryParse(m['pollExpiresAt'] as String)
                  : null,
            );
            final remotePoll = ActivePoll(
              id: 'fs_$id',
              data: pollData,
              creatorName: m['senderName'] as String? ?? 'Member',
              creatorId: senderId,
              createdAt: ts,
              isPinned: false,
            );
            unawaited(_pollService.addPoll(widget.groupId, remotePoll));
          }
          continue;
        }

        // ── Text / voice_note (existing path) ──────────────────────────────
        final chatMsg = ChatMessage(
          id: id,
          senderId: senderId,
          senderName: m['senderName'] as String? ?? 'Member',
          senderAvatar: m['senderAvatar'] as String? ?? '',
          message: m['message'] as String? ?? '',
          timestamp: ts,
          isMe: false,
          isVoiceNote: msgType == 'voice_note',
          audioUrl: m['audioUrl'] as String?,
          audioDuration: m['audioDuration'] as int?,
        );
        // Only add if not already present by id
        if (!_messages.any((existing) => existing.id == id)) {
          _messages.add(chatMsg);
          added = true;
        }
      }
      if (added) {
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        setState(() {});
        // Auto-scroll to latest
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint('[GroupChat] Firestore stream error: $e');
    });
  }

  Future<void> _loadMessages() async {
    await _invitationService.initialize();
    await _onboardingService.initialize();
    await _savedMessageService.initialize();

    // Start with an empty message list — real messages come from
    // persisted storage and Firestore below (no dummy data injected).
    _messages = [];

    // Load system messages for this group (join/leave events)
    final systemMessages = _invitationService.getGroupSystemMessages(widget.groupId);
    for (final sysMsg in systemMessages) {
      _messages.add(ChatMessage(
        id: 'sys_${sysMsg.timestamp.millisecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'System',
        senderAvatar: '',
        message: sysMsg.displayText,
        timestamp: sysMsg.timestamp,
        isMe: false,
        isSystem: true,
      ));
    }

    // Sort by timestamp
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Load persisted thread replies for this group
    await _loadPersistedThreadReplies();

    // Load persisted unsend states
    await _loadPersistedUnsendStates();

    // Load persisted user messages (text, images, docs, reactions)
    await _loadPersistedUserMessages();

    // Load forwarded messages from other screens (via forward_message_sheet)
    await _loadForwardedMessages();

    // Load meetup notification for this group (if any)
    await _loadMeetupNotification();

    // Load persisted polls for this group
    await _pollService.loadPolls(widget.groupId);

    // ── Load existing Firestore messages (cross-device history) ──────────
    // Fetch once on open so messages from other users appear immediately,
    // before the real-time stream delivers its first update.
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final firestoreMsgs = await FirestoreService()
          .groupMessagesStream(widget.groupId)
          .first
          .timeout(const Duration(seconds: 5));

      for (final m in firestoreMsgs) {
        final id = m['id'] as String? ?? '';
        if (id.isEmpty) continue;
        _firestoreMsgIds.add(id); // register all so stream doesn't re-add
        final senderId = m['senderId'] as String? ?? '';
        final isMe = senderId == currentUid;
        final tsRaw = m['timestamp'];
        final DateTime ts;
        if (tsRaw is String) {
          ts = DateTime.tryParse(tsRaw) ?? DateTime.now();
        } else if (tsRaw is Timestamp) {
          ts = tsRaw.toDate();
        } else {
          ts = DateTime.now();
        }
        final msgType = m['type'] as String? ?? 'text';

        // ── Reactions — merged FIRST, before any type-specific continue ────
        // Previously this block lived after image/location/document/contact/
        // poll branches which all `continue` before reaching it, so reactions
        // on those message types were silently dropped on history load.
        final rxnRaw = m['reactions'];
        if (rxnRaw is Map && rxnRaw.isNotEmpty) {
          final rxnMap = <String, int>{};
          rxnRaw.forEach((k, v) {
            final count = (v as num?)?.toInt() ?? 0;
            if (count > 0) rxnMap[k as String] = count;
          });
          if (rxnMap.isNotEmpty) _reactions[id] = rxnMap;
        }

        // ── reactionUsers → seed _myReactions on history load ─────────────
        // Restores which emoji this user previously reacted with so that
        // _toggleReaction's replace logic works correctly on first interaction.
        final rxnUsersRaw = m['reactionUsers'];
        if (rxnUsersRaw is Map) {
          final myEmoji = rxnUsersRaw[currentUid] as String?;
          if (myEmoji != null && myEmoji.isNotEmpty) {
            _myReactions[id] = myEmoji;
          }
        }

        // ── Image history (cross-device) ───────────────────────────────────
        if (msgType == 'image') {
          final imageUrl = m['imageUrl'] as String? ?? '';
          if (imageUrl.isNotEmpty &&
              !_imageMessages.any((img) => img.imageUrl == imageUrl)) {
            _imageMessages.add(_GroupImageMessage(
              imageUrl: imageUrl,
              isMe: isMe,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
            ));
          }
          continue;
        }

        // ── Location history (cross-device) ───────────────────────────────
        if (msgType == 'location') {
          final lat = (m['latitude'] as num?)?.toDouble();
          final lng = (m['longitude'] as num?)?.toDouble();
          final locLabel = m['locationLabel'] as String? ?? 'Location';
          final alreadyHave = _imageMessages.any((img) =>
              img.isLocationPin &&
              img.latitude == lat &&
              img.longitude == lng &&
              img.senderId == senderId);
          if (!alreadyHave) {
            _imageMessages.add(_GroupImageMessage(
              imageUrl: 'location_pin',
              isMe: isMe,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
              isLocationPin: true,
              latitude: lat,
              longitude: lng,
              locationLabel: locLabel,
            ));
          }
          continue;
        }

        // ── Document history (cross-device) ───────────────────────────────
        if (msgType == 'document') {
          final docName = m['documentName'] as String? ?? 'Document';
          final docSize = (m['documentSize'] as num?)?.toInt();
          final docUrl  = m['documentUrl'] as String? ?? '';
          if (!_documentMessages.any((d) =>
              d.senderId == senderId && d.fileName == docName)) {
            _documentMessages.add(_GroupDocumentMessage(
              fileName: docName,
              fileSize: docSize,
              fileUrl: docUrl,
              isMe: isMe,
              timestamp: ts,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              senderId: senderId,
            ));
          }
          continue;
        }

        // ── Contact history (cross-device) ────────────────────────────────
        if (msgType == 'contact') {
          final contactMsg = '\u{1F464} Contact: '
              '${m['contactName'] as String? ?? 'Unknown'} - '
              '${m['contactPhone'] as String? ?? ''}';
          if (!_messages.any((e) => e.id == id)) {
            _messages.add(ChatMessage(
              id: id,
              senderId: senderId,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              message: contactMsg,
              timestamp: ts,
              isMe: isMe,
            ));
          }
          continue;
        }

        // ── Poll history (cross-device) ───────────────────────────────────
        if (msgType == 'poll') {
          final pollQuestion = m['pollQuestion'] as String? ?? '';
          final pollAnnounceId = 'fs_poll_$id';
          if (pollQuestion.isNotEmpty &&
              !_messages.any((e) => e.id == pollAnnounceId)) {
            _messages.add(ChatMessage(
              id: pollAnnounceId,
              senderId: senderId,
              senderName: m['senderName'] as String? ?? 'Member',
              senderAvatar: m['senderAvatar'] as String? ?? '',
              message: '\u{1F4CA} Poll: "$pollQuestion"',
              timestamp: ts,
              isMe: isMe,
              isSystem: true,
            ));
          }
          // Restore the ActivePoll locally if not already present
          final rawOptions = m['pollOptions'];
          if (rawOptions is List && !_polls.any((p) => p.id == 'fs_$id')) {
            final pollData = PollData(
              question: pollQuestion,
              options: rawOptions.map((e) => e as String).toList(),
              allowMultiple: m['pollAllowMultiple'] as bool? ?? false,
              isCalendarMode: m['pollIsCalendarMode'] as bool? ?? false,
              expiresAt: m['pollExpiresAt'] != null
                  ? DateTime.tryParse(m['pollExpiresAt'] as String)
                  : null,
            );
            final remotePoll = ActivePoll(
              id: 'fs_$id',
              data: pollData,
              creatorName: m['senderName'] as String? ?? 'Member',
              creatorId: senderId,
              createdAt: ts,
              isPinned: false,
            );
            unawaited(_pollService.addPoll(widget.groupId, remotePoll));
          }
          continue;
        }

        // ── Text / voice_note history ──────────────────────────────────────
        if (!_messages.any((e) => e.id == id)) {
          _messages.add(ChatMessage(
            id: id,
            senderId: senderId,
            senderName: m['senderName'] as String? ?? 'Member',
            senderAvatar: m['senderAvatar'] as String? ?? '',
            message: m['message'] as String? ?? '',
            timestamp: ts,
            isMe: isMe,
            isVoiceNote: msgType == 'voice_note',
            audioUrl: m['audioUrl'] as String?,
            audioDuration: m['audioDuration'] as int?,
          ));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Firestore history load error: $e');
    }

    // Re-sort everything
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      // Auto-open thread panel if navigated from Saved tab with a thread target
      _autoOpenThreadIfNeeded();
    });
  }

  /// Reload only forwarded messages and meetup notifications, then merge new ones in.
  /// Called by the periodic timer to pick up cards forwarded while the chat is open.
  Future<void> _reloadForwardedMessages() async {
    try {
      final key = 'group_messages_${widget.groupId}';
      final raw = await BrowserStorage.getString(key);
      if (raw == null) return;
      final List<dynamic> all = json.decode(raw);
      bool added = false;
      for (final m in all) {
        final id = m['id'] as String? ?? '';
        if (id.isEmpty) continue;

        final msgType = m['type'] as String? ?? 'text';

        // ── Image forwarded to this group ─────────────────────────────────
        if (msgType == 'image') {
          // Already loaded? Check _imageMessages by matching timestamp + sender
          // (image messages don't have an 'id' tracked in _imageMessages so we
          // use the forwarded msg id stored in the imageUrl field as fallback).
          final alreadyLoaded = _imageMessages.any(
            (img) => img.imageUrl == (m['imageUrl'] as String? ?? id),
          );
          if (alreadyLoaded) continue;
          final imageUrl = m['imageUrl'] as String? ?? '';
          if (imageUrl.isEmpty) continue;
          // Restore bytes if the forward sheet stored them as base64
          Uint8List? restoredBytes;
          final b64 = m['bytesBase64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            try { restoredBytes = base64Decode(b64); } catch (_) {}
          }
          _imageMessages.add(_GroupImageMessage(
            imageUrl: imageUrl,
            bytes: restoredBytes,
            isMe: true,
            timestamp: DateTime.parse(m['timestamp'] as String),
            senderName: m['senderName'] as String? ?? 'You',
            senderAvatar: '#FF975C',
            senderId: 'current_user',
          ));
          added = true;
          continue;
        }

        // ── Text / card message ──────────────────────────────────────────
        if (_messages.any((msg) => msg.id == id)) continue;
        Map<String, dynamic>? safeMap(dynamic raw) {
          if (raw == null) return null;
          if (raw is Map<String, dynamic>) return raw;
          if (raw is Map) return Map<String, dynamic>.from(raw);
          return null;
        }
        final rawMeetupData = safeMap(m['meetupData']);
        final rawGroupData  = safeMap(m['groupData']);
        final rawItemData   = safeMap(m['itemData']);
        final rawEventData  = safeMap(m['eventData']);
        _messages.add(ChatMessage(
          id: id,
          senderId: m['senderId'] as String? ?? 'current_user',
          senderName: m['senderName'] as String? ?? 'You',
          senderAvatar: '#FF975C',
          message: m['message'] as String? ?? '',
          timestamp: DateTime.parse(m['timestamp'] as String),
          isMe: true,
          isMeetupCard: (m['isMeetupCard'] as bool? ?? false) || rawMeetupData != null,
          meetupData: rawMeetupData,
          isGroupCard: (m['isGroupCard'] as bool? ?? false) || rawGroupData != null,
          groupData: rawGroupData,
          isItemCard: (m['isItemCard'] as bool? ?? false) || rawItemData != null,
          itemData: rawItemData,
          isEventCard: (m['isEventCard'] as bool? ?? false) || rawEventData != null,
          eventData: rawEventData,
        ));
        added = true;
      }
      if (added && mounted) {
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {}
  }

  /// If the screen was opened with [openThreadForMessageId], find that message
  /// in the loaded messages list and automatically open its thread panel.
  void _autoOpenThreadIfNeeded() {
    final targetId = widget.openThreadForMessageId;
    if (targetId == null || targetId.isEmpty) return;

    // Find the root message in the loaded messages
    final rootMsg = _messages.cast<ChatMessage?>().firstWhere(
      (m) => m!.id == targetId,
      orElse: () => null,
    );
    if (rootMsg != null) {
      _openThread(rootMsg);
    }
  }

  // ── Thread reply persistence ─────────────────────────────────────────
  Future<void> _loadPersistedThreadReplies() async {
    try {
      final raw = await BrowserStorage.getString(_threadStorageKey);
      if (raw != null) {
        final Map<String, dynamic> decoded = json.decode(raw);
        decoded.forEach((msgId, repliesJson) {
          final List<dynamic> list = repliesJson as List<dynamic>;
          _threadReplies[msgId] = list
              .map((e) => ThreadReply.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
      // Silently handle — first launch or corrupt data
    }
  }

  Future<void> _persistThreadReplies() async {
    try {
      final Map<String, dynamic> data = {};
      _threadReplies.forEach((msgId, replies) {
        if (replies.isNotEmpty) {
          data[msgId] = replies.map((r) => r.toJson()).toList();
        }
      });
      await BrowserStorage.setString(_threadStorageKey, json.encode(data));
    } catch (_) {
      // Silently handle
    }
  }

  // ── Unsend state persistence ──────────────────────────────────────────
  Future<void> _loadPersistedUnsendStates() async {
    try {
      final hiddenRaw = await BrowserStorage.getString(_hiddenMsgKey);
      if (hiddenRaw != null) {
        final List<dynamic> decoded = json.decode(hiddenRaw);
        _hiddenMessageIds.addAll(decoded.cast<String>());
      }
      final deletedRaw = await BrowserStorage.getString(_deletedEveryoneKey);
      if (deletedRaw != null) {
        final List<dynamic> decoded = json.decode(deletedRaw);
        _deletedForEveryoneIds.addAll(decoded.cast<String>());
      }
    } catch (_) {
      // Silently handle — first launch or corrupt data
    }
  }

  Future<void> _persistUnsendStates() async {
    try {
      await BrowserStorage.setString(
          _hiddenMsgKey, json.encode(_hiddenMessageIds.toList()));
      await BrowserStorage.setString(
          _deletedEveryoneKey, json.encode(_deletedForEveryoneIds.toList()));
    } catch (_) {
      // Silently handle
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final optimisticId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';

    setState(() {
      _messages.add(ChatMessage(
        id: optimisticId,
        senderId: currentUid,
        senderName: _onboardingService.name ?? 'You',
        senderAvatar: _myPhotoUrl,
        message: text,
        timestamp: DateTime.now(),
        isMe: true,
      ));
      _messageStatuses[optimisticId] = MessageStatus.sending;
    });
    // Track optimistic id so stream doesn't add it again
    _firestoreMsgIds.add(optimisticId);

    _messageController.clear();
    _fireMessageSentNotifier();

    // ── AI safety pre-filter (best-effort, safe-by-default on error) ────
    final safetyResult = await MessageSafetyService().classify(text);
    if (safetyResult == MessageSafetyResult.hold) {
      // Remove the optimistic message we added above
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == msgId);
          _messageStatuses.remove(msgId);
        });
        _firestoreMsgIds.remove(msgId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Your message could not be sent — it may violate our community guidelines.',
            ),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    // ── Write to Firestore for real cross-device delivery ───────────────
    try {
      final firestoreId = await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: text,
      );
      // ── Patch local message to use the real Firestore doc ID ──────────
      // This is critical: emoji reactions write to group_messages/{firestoreId}.
      // If msg.id stays as the optimistic 'msg_...' key the reaction Firestore
      // write targets a non-existent document and the reaction never persists.
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == optimisticId);
          if (idx >= 0) {
            final old = _messages[idx];
            _messages[idx] = ChatMessage(
              id: firestoreId,
              senderId: old.senderId,
              senderName: old.senderName,
              senderAvatar: old.senderAvatar,
              message: old.message,
              timestamp: old.timestamp,
              isMe: old.isMe,
              replyToText: old.replyToText,
              replyToSender: old.replyToSender,
            );
          }
          // Re-key status and firestoreMsgIds to real doc ID
          final status = _messageStatuses.remove(optimisticId);
          if (status != null) _messageStatuses[firestoreId] = status;
          _firestoreMsgIds.remove(optimisticId);
          _firestoreMsgIds.add(firestoreId);
          _messageStatuses[firestoreId] = MessageStatus.sent;
        });
      }
      // Persist locally too so message survives navigation
      await _persistUserTextMessages();
      // Mark delivered after Firestore write confirmed
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _messageStatuses[firestoreId] = MessageStatus.delivered);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Firestore send error: $e');
      // Still show as sent locally even if Firestore fails (optimistic ID kept)
      if (mounted) setState(() => _messageStatuses[optimisticId] = MessageStatus.sent);
      await _persistUserTextMessages();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Search logic ────────────────────────────────────────────────────────
  void _performGroupSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _searchMatches = [];
        _currentMatchIndex = -1;
        return;
      }
      final q = query.toLowerCase();
      _searchMatches = [];
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].message.toLowerCase().contains(q)) {
          _searchMatches.add(i);
        }
      }
      _currentMatchIndex = _searchMatches.isNotEmpty ? 0 : -1;
      if (_currentMatchIndex >= 0) {
        _scrollToMessage(_searchMatches[_currentMatchIndex]);
      }
    });
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatches.length;
    });
    _scrollToMessage(_searchMatches[_currentMatchIndex]);
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _scrollToMessage(_searchMatches[_currentMatchIndex]);
  }

  void _scrollToMessage(int index) {
    final offset = index * 80.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Navigate to DM from member avatar ─────────────────────────────────
  void _openDMWithMember(String senderId, String senderName, String senderAvatar) {
    if (senderId == 'current_user' || senderId == 'system') return;
    Navigator.pushNamed(context, '/dm_chat', arguments: {
      'recipientId': senderId,
      'recipientName': senderName,
      'recipientAvatarColor': senderAvatar.startsWith('#') ? senderAvatar : '#FF975C',
    });
  }

  // ── Emoji reactions ────────────────────────────────────────────────────

  /// Shallow equality check for reaction maps — avoids unnecessary setState.
  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  Future<void> _showEmojiPicker(String messageId) async {
    final emoji = await showEmojiReactionPicker(context);
    if (emoji != null && mounted) {
      _toggleReaction(messageId, emoji);
    }
  }

  void _toggleReaction(String messageId, String emoji) {
    bool adding = false;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Capture the previous emoji for this user BEFORE setState so we can
    // issue a Firestore remove for it outside the setState block.
    final previousEmoji = _myReactions[messageId];

    setState(() {
      // Work on a mutable copy so we never accidentally clear other users'
      // reactions that are already in the map.
      final msgReactions = Map<String, int>.from(_reactions[messageId] ?? {});

      if (previousEmoji == emoji) {
        // ── Same emoji tapped again → remove this user's reaction ─────────
        final newCount = (msgReactions[emoji] ?? 1) - 1;
        if (newCount <= 0) {
          msgReactions.remove(emoji);
        } else {
          msgReactions[emoji] = newCount;
        }
        _myReactions.remove(messageId);
        adding = false;
      } else {
        // ── New or different emoji ────────────────────────────────────────
        // Step 1: decrement (and remove if zero) the user's previous emoji
        // from the local count — but leave all other users' emojis intact.
        if (previousEmoji != null) {
          final prevCount = (msgReactions[previousEmoji] ?? 1) - 1;
          if (prevCount <= 0) {
            msgReactions.remove(previousEmoji);
          } else {
            msgReactions[previousEmoji] = prevCount;
          }
        }

        // Step 2: increment the new emoji count.
        msgReactions[emoji] = (msgReactions[emoji] ?? 0) + 1;
        _myReactions[messageId] = emoji;
        adding = true;

        // ── Notify the message author (fire-and-forget) ───────────────────
        final msg = _messages.where((m) => m.id == messageId).isNotEmpty
            ? _messages.firstWhere((m) => m.id == messageId)
            : null;
        if (msg != null &&
            msg.senderId.isNotEmpty &&
            msg.senderId != 'system' &&
            msg.senderId != myUid) {
          final myName = _onboardingService.name ?? 'Someone';
          HuddlNotificationService().messageReaction(
            recipientId: msg.senderId,
            reactorName: myName,
            emoji: emoji,
            messagePreview: msg.message.length > 60
                ? '${msg.message.substring(0, 60)}…'
                : msg.message,
            contextType: 'group',
            groupId: widget.groupId,
            groupName: widget.groupName,
          ).catchError((e) {
            if (kDebugMode) debugPrint('[GroupChat] reaction notif error: $e');
          });
        }
      }

      if (msgReactions.isEmpty) {
        _reactions.remove(messageId);
      } else {
        _reactions[messageId] = msgReactions;
      }
    });

    _persistReactions();

    // ── Remove the old emoji from Firestore (if replacing) ───────────────
    if (previousEmoji != null && previousEmoji != emoji) {
      FirestoreService().updateMessageReaction(
        messageId: messageId,
        emoji: previousEmoji,
        adding: false,
      );
    }

    // ── Add/remove the tapped emoji in Firestore ──────────────────────────
    FirestoreService().updateMessageReaction(
      messageId: messageId,
      emoji: emoji,
      adding: adding,
    );
  }

  void _openThread(ChatMessage msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadReplyScreen(
          rootMessage: msg,
          groupId: widget.groupId,
          groupName: widget.groupName,
          existingReplies: _threadReplies[msg.id] ?? [],
          onReplySent: (reply) {
            setState(() {
              _threadReplies.putIfAbsent(msg.id, () => []);
              _threadReplies[msg.id]!.add(reply);
            });
            _persistThreadReplies();
          },
        ),
      ),
    );
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Message copied to clipboard'),
          ],
        ),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatSavedDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Saved threads for this group ───────────────────────────────────
  void _showSavedThreadsForGroup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        // Read threads inside builder so the list is always current
        final threads = _savedMessageService.getSavedThreadsForGroup(widget.groupId);
        return SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.topic, color: HuddlColors.blue, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Saved Threads',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${threads.length}',
                      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: context.hc.divider),
              if (threads.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: HuddlColors.blue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.topic_outlined, size: 36, color: HuddlColors.blue),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No saved threads',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            'Long press on a message with replies and select "Save reply thread" to save it under a topic.',
                            style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: context.hc.divider),
                    itemBuilder: (_, i) {
                      final thread = threads[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: HuddlColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.topic, color: HuddlColors.blue, size: 22),
                        ),
                        title: Text(
                          thread.topicName,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              thread.rootMessageText,
                              style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 12, color: context.hc.textTertiary),
                                const SizedBox(width: 4),
                                Text(
                                  '${thread.totalMessages} messages',
                                  style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatSavedDate(thread.savedAt),
                                  style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Navigate to group
                            IconButton(
                              icon: const Icon(Icons.open_in_new, size: 18, color: HuddlColors.primary),
                              tooltip: 'Go to group',
                              onPressed: () {
                                Navigator.pop(c);
                                Navigator.pushNamed(context, '/group_chat', arguments: {
                                  'groupId': thread.groupId,
                                  'groupName': thread.groupName,
                                  'groupImageUrl': thread.groupImageUrl,
                                });
                              },
                            ),
                            // Delete
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: context.hc.textTertiary),
                              onPressed: () async {
                                await _savedMessageService.unsaveThread(thread.id);
                                if (c.mounted) Navigator.pop(c);
                                _showSavedThreadsForGroup();
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(c);
                          // Show thread detail in a new bottom sheet
                          _showThreadDetail(thread);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        );
      },
    );
  }

  void _showThreadDetail(dynamic thread) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.topic, color: HuddlColors.blue, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        thread.topicName,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        Navigator.pushNamed(context, '/group_chat', arguments: {
                          'groupId': thread.groupId,
                          'groupName': thread.groupName,
                          'groupImageUrl': thread.groupImageUrl,
                        });
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text('Go to group',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(foregroundColor: HuddlColors.primary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '${thread.groupName}',
                      style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${thread.totalMessages} messages',
                      style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: context.hc.divider),
              // Root message
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Root message
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: HuddlColors.primary, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                thread.rootSenderName,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatSavedDate(thread.rootTimestamp),
                                style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            thread.rootMessageText,
                            style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    // Replies
                    ...thread.replies.map<Widget>((reply) => Container(
                          margin: const EdgeInsets.only(left: 16, bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: reply.isMe ? HuddlColors.peachLight : HuddlColors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    reply.isMe ? 'You' : reply.senderName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: reply.isMe ? HuddlColors.primary : HuddlColors.blue,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatSavedDate(reply.timestamp),
                                    style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reply.message,
                                style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textPrimary, height: 1.4),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Unsend message ──────────────────────────────────────────────────
  void _showUnsendDialog(ChatMessage msg) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_sweep_outlined, size: 32, color: HuddlColors.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'Unsend message?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose how you want to unsend this message.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Unsend for everyone
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    setState(() {
                      _deletedForEveryoneIds.add(msg.id);
                    });
                    _persistUnsendStates();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Message unsent for everyone'),
                          ],
                        ),
                        backgroundColor: HuddlColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.group_outlined, size: 20),
                  label: Text('Unsend for everyone',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Unsend just for me
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    setState(() {
                      _hiddenMessageIds.add(msg.id);
                    });
                    _persistUnsendStates();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Message unsent for you'),
                          ],
                        ),
                        backgroundColor: HuddlColors.textSecondary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 20),
                  label: Text('Unsend just for me',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: HuddlColors.textDark,
                    side: BorderSide(color: context.hc.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Cancel
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w500, color: context.hc.textTertiary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Save message / thread under a named topic ───────────────────────
  void _showSaveThreadDialog(ChatMessage rootMsg) {
    // Collect thread replies from the _threadReplies map (may be empty —
    // a single message with no replies can still be saved under a topic).
    final threadReplies = _threadReplies[rootMsg.id] ?? [];

    final topicController = TextEditingController();
    // Existing topic names for suggestions / duplicate detection
    final existingTopics = _savedMessageService.savedTopicNames;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          // Live duplicate check as user types
          final typed = topicController.text.trim().toLowerCase();
          final isExisting = typed.isNotEmpty &&
              existingTopics
                  .any((t) => t.trim().toLowerCase() == typed);

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: HuddlColors.blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.topic_outlined, size: 32, color: HuddlColors.blue),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      threadReplies.isEmpty ? 'Save message' : 'Save reply thread',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      threadReplies.isEmpty
                          ? 'Save this message under a topic'
                          : '${threadReplies.length + 1} messages in this thread',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: context.hc.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Thread preview
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: HuddlColors.primary, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rootMsg.senderName,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                          Text(
                            rootMsg.message,
                            style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (threadReplies.isNotEmpty)
                          Text(
                            '+ ${threadReplies.length} ${threadReplies.length == 1 ? 'reply' : 'replies'}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Existing topic chips (tap to reuse) ──────────────
                    if (existingTopics.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Add to existing topic',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: existingTopics.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, i) {
                            final name = existingTopics[i];
                            final selected =
                                topicController.text.trim().toLowerCase() ==
                                    name.trim().toLowerCase();
                            return GestureDetector(
                              onTap: () {
                                topicController.text = name;
                                topicController.selection = TextSelection.collapsed(
                                    offset: name.length);
                                setDialogState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? HuddlColors.blue
                                      : HuddlColors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? HuddlColors.blue
                                        : HuddlColors.blue.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: selected
                                        ? HuddlColors.white
                                        : HuddlColors.blue,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Topic name text field ───────────────────────────
                    TextField(
                      controller: topicController,
                      autofocus: existingTopics.isEmpty,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Topic name',
                        labelStyle: GoogleFonts.poppins(
                            fontSize: 14, color: context.hc.textTertiary),
                        hintText: existingTopics.isEmpty
                            ? 'e.g. Thursday cafe meetup'
                            : 'New topic or pick one above',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: context.hc.textTertiary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.hc.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isExisting ? HuddlColors.blue : HuddlColors.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        // Suffix clear button
                        suffixIcon: topicController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  topicController.clear();
                                  setDialogState(() {});
                                },
                              )
                            : null,
                      ),
                    ),

                    // ── Merge notice ─────────────────────────────────────
                    if (isExisting) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: HuddlColors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: HuddlColors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.merge_type_rounded,
                                size: 16, color: HuddlColors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This thread will be added to the existing "${topicController.text.trim()}" topic',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: HuddlColors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(c),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: HuddlColors.primary),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text('Cancel',
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.primary)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final topic = topicController.text.trim();
                              if (topic.isEmpty) return;
                              Navigator.pop(c);
                              unawaited(_saveThread(rootMsg, threadReplies, topic));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HuddlColors.blue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                            child: Text(
                              isExisting
                                  ? 'Add to topic'
                                  : threadReplies.isEmpty
                                      ? 'Save message'
                                      : 'Save thread',
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.white),
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
        },
      ),
    );
  }

  Future<void> _saveThread(ChatMessage rootMsg, List<ThreadReply> replies, String topicName) async {
    // Determine whether this is a merge before saving (for snackbar label)
    final existingTopics = _savedMessageService.savedTopicNames;
    final isMerge = existingTopics
        .any((t) => t.trim().toLowerCase() == topicName.trim().toLowerCase());

    await _savedMessageService.saveThread(
      topicName: topicName,
      rootMessageId: rootMsg.id,
      rootMessageText: rootMsg.message,
      rootSenderName: rootMsg.senderName,
      rootTimestamp: rootMsg.timestamp,
      replies: replies
          .map((r) => SavedThreadMessage(
                messageId: r.id,
                message: r.message,
                senderName: r.senderName,
                timestamp: r.timestamp,
                isMe: r.isMe,
              ))
          .toList(),
      groupId: widget.groupId,
      groupName: widget.groupName,
      groupImageUrl: widget.groupImageUrl,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isMerge ? Icons.merge_type_rounded : Icons.topic,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isMerge
                    ? 'Thread added to "$topicName"'
                    : 'Thread saved as "$topicName"',
              ),
            ),
          ],
        ),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Block user in group ───────────────────────────────────────────
  void _showBlockMemberDialog(String memberId, String memberName) {
    final isBlocked = _blockService.isUserBlocked(memberId);
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                isBlocked ? 'Unblock $memberName?' : 'Block $memberName?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                isBlocked
                    ? 'Their messages will be visible in this group again.'
                    : 'Their messages will be hidden from you in this group and DMs.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: HuddlColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final wasBlocked = isBlocked;
                        await _blockService.toggleBlock(memberId);
                        setState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(wasBlocked
                                  ? '$memberName has been unblocked'
                                  : '$memberName has been blocked'),
                              backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.error,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(isBlocked ? 'Unblock' : 'Block',
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.white)),
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

  // ── Report User dialog (profile-level, from message long-press) ──────────
  void _showReportUserDialog(String targetUserId, String targetName) {
    final reportService = ReportService();
    ReportType? selectedType;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flag_outlined, size: 22, color: HuddlColors.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Report $targetName',
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w700, color: context.hc.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Why are you reporting this user?',
                  style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                RadioGroup<ReportType>(
                  groupValue: selectedType,
                  onChanged: (v) => setDialogState(() => selectedType = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ReportType.values.map((type) => InkWell(
                      onTap: () => setDialogState(() => selectedType = type),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Radio<ReportType>(
                              value: type,
                              activeColor: HuddlColors.primary,
                            ),
                            Expanded(
                              child: Text(type.label,
                                  style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(c),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: HuddlColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Cancel',
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selectedType == null
                            ? null
                            : () async {
                                Navigator.pop(c);
                                final ok = await reportService.submitReport(
                                  contentId: targetUserId,
                                  targetUserId: targetUserId,
                                  type: selectedType!,
                                  context: ReportContext.userProfile,
                                  groupId: widget.groupId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Report submitted. Thank you.'
                                          : 'Could not submit report. Please try again.'),
                                      backgroundColor: ok ? HuddlColors.primary : HuddlColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.error,
                          disabledBackgroundColor: HuddlColors.error.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: Text('Report',
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Report message dialog ──────────────────────────────────────────────
  void _showReportMessageDialog(String messageId, String targetUserId, String senderName) {
    final reportService = ReportService();
    ReportType? selectedType;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.flag_outlined, size: 22, color: HuddlColors.error),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Report message',
                      style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w700, color: context.hc.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Why are you reporting this message from $senderName?',
                  style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                RadioGroup<ReportType>(
                  groupValue: selectedType,
                  onChanged: (v) => setDialogState(() => selectedType = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ReportType.values.map((type) => InkWell(
                      onTap: () => setDialogState(() => selectedType = type),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Radio<ReportType>(
                              value: type,
                              activeColor: HuddlColors.primary,
                            ),
                            Text(type.label,
                                style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary)),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(c),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: HuddlColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Cancel',
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selectedType == null
                            ? null
                            : () async {
                                Navigator.pop(c);
                                final ok = await reportService.submitReport(
                                  contentId: messageId,
                                  targetUserId: targetUserId,
                                  type: selectedType!,
                                  context: ReportContext.groupMessage,
                                  groupId: widget.groupId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Report submitted. Thank you.'
                                          : 'Could not submit report. Please try again.'),
                                      backgroundColor: ok ? HuddlColors.primary : HuddlColors.error,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.error,
                          disabledBackgroundColor: HuddlColors.error.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: Text('Report',
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add Member sheet (private group admin only) ────────────────────────
  void _showAddMemberSheet() {
    // Show real borough members from Firestore (excluding existing members).
    // availableMembers will be populated via _loadGroupMembers in a future.
    final availableMembers = _groupMembers
        .where((m) => !m.isAdmin && m.id != 'current_user')
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add Member', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Select a member from your borough to add to this private group.',
                style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: availableMembers.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: context.hc.divider),
                itemBuilder: (_, i) {
                  final m = availableMembers[i];
                  return ListTile(
                    leading: MemberAvatar(name: m.name, size: 42, accentColor: m.accentColor, showOnlineDot: false, isOnline: false),
                    title: Text(m.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: context.hc.textPrimary)),
                    trailing: SizedBox(
                      width: 80,
                      height: 34,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(c);
                          setState(() => _groupMembers.add(m));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${m.name} added to group'), backgroundColor: HuddlColors.primary,
                              behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: HuddlColors.primary, elevation: 0, padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        child: Text('Add', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Remove Member sheet (private group admin only) ─────────────────────
  void _showRemoveMemberSheet() {
    // Only show non-admin members that can be removed (not the creator)
    final removable = _groupMembers.where((m) => !m.isAdmin && m.id != 'current_user').toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Remove Member', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Select a member to remove from this private group.',
                style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary)),
            ),
            const SizedBox(height: 12),
            if (removable.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No members to remove.', style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary)),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: removable.length,
                  separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: context.hc.divider),
                  itemBuilder: (_, i) {
                    final m = removable[i];
                    return ListTile(
                      leading: MemberAvatar(name: m.name, size: 42, accentColor: m.accentColor, showOnlineDot: false, isOnline: false),
                      title: Text(m.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: context.hc.textPrimary)),
                      trailing: SizedBox(
                        width: 90,
                        height: 34,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(c);
                            _confirmRemoveMember(m);
                          },
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: HuddlColors.error), padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                          child: Text('Remove', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.error)),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveMember(_GroupMember member) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove ${member.name}?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
        content: Text('${member.name} will be removed from this private group and will no longer be able to see group messages.',
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: GoogleFonts.poppins(color: context.hc.textSecondary))),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() => _groupMembers.removeWhere((gm) => gm.id == member.id));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${member.name} removed from group'), backgroundColor: HuddlColors.primary,
                  behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              );
            },
            child: Text('Remove', style: GoogleFonts.poppins(color: HuddlColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Add Admin sheet (private group admin only) ─────────────────────────
  void _showAddAdminSheet() {
    // Only show non-admin members
    final nonAdmins = _groupMembers.where((m) => !m.isAdmin).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings, size: 24, color: HuddlColors.blue),
                  const SizedBox(width: 10),
                  Text('Add Admin', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Admins can add and remove members, edit group details, and manage the group.',
                style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            if (nonAdmins.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.admin_panel_settings_outlined, size: 48, color: context.hc.textTertiary),
                    const SizedBox(height: 12),
                    Text('All members are already admins.', style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary)),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: nonAdmins.length,
                  separatorBuilder: (_, __) => Divider(height: 1, indent: 56, color: context.hc.divider),
                  itemBuilder: (_, i) {
                    final m = nonAdmins[i];
                    return ListTile(
                      leading: MemberAvatar(name: m.name, size: 42, accentColor: m.accentColor, showOnlineDot: false, isOnline: false),
                      title: Text(m.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: context.hc.textPrimary)),
                      subtitle: Text('Member', style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
                      trailing: SizedBox(
                        width: 110,
                        height: 34,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(c);
                            _confirmMakeAdmin(m);
                          },
                          icon: const Icon(Icons.shield_outlined, size: 16, color: HuddlColors.white),
                          label: Text('Make Admin', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: HuddlColors.blue, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmMakeAdmin(_GroupMember member) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Make ${member.name} an admin?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
        content: Text(
          '${member.name} will have admin rights including adding/removing members and editing group details.',
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: GoogleFonts.poppins(color: context.hc.textSecondary))),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() {
                final idx = _groupMembers.indexWhere((gm) => gm.id == member.id);
                if (idx != -1) {
                  _groupMembers[idx] = _GroupMember(
                    id: member.id, name: member.name,
                    accentColor: member.accentColor, isAdmin: true,
                  );
                }
                _adminIds.add(member.id);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('${member.name} is now an admin'),
                  ]),
                  backgroundColor: HuddlColors.teal,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text('Confirm', style: GoogleFonts.poppins(color: HuddlColors.teal, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Leave group confirmation dialog (matching screenshot design) ───────
  void _showLeaveGroupDialog() {
    showDialog(
      context: context,
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
                        final userName = _onboardingService.name ?? 'You';

                        // 1. Remove from invitation service
                        await _invitationService.leaveGroup(widget.groupId, userName);

                        // 2. Remove from DefaultGroupService memberships
                        final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
                        final userId = firebaseUid ?? 'user_${_onboardingService.name?.hashCode ?? 0}';
                        await DefaultGroupService().leaveGroup(userId, widget.groupId);

                        // 3. Remove from user-created groups storage
                        try {
                          final raw = await BrowserStorage.getString('user_created_groups_v1');
                          if (raw != null) {
                            final List<dynamic> groups = json.decode(raw);
                            groups.removeWhere((j) => (j as Map<String, dynamic>)['id'] == widget.groupId);
                            await BrowserStorage.setString('user_created_groups_v1', json.encode(groups));
                          }
                        } catch (_) {}

                        // 4. Persist to left-groups list so it is never re-added on reload
                        try {
                          final leftRaw = await BrowserStorage.getString('left_groups_v1');
                          final List<String> leftIds = leftRaw != null
                              ? List<String>.from(json.decode(leftRaw) as List)
                              : [];
                          if (!leftIds.contains(widget.groupId)) {
                            leftIds.add(widget.groupId);
                            await BrowserStorage.setString('left_groups_v1', json.encode(leftIds));
                          }
                        } catch (_) {}

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Left ${widget.groupName}'),
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

  // ── Share group logic ──────────────────────────────────────────────────
  void _handleShareGroup() {
    // Default groups cannot be shared — they are created only via onboarding
    if (widget.isDefaultGroup) {
      _showCannotShareDefaultDialog();
      return;
    }
    // Non-default (public/discover) groups can be shared
    _showShareGroupSheet();
  }

  void _showCannotShareDefaultDialog() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline, size: 32, color: HuddlColors.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'Cannot share this group',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Default community groups are automatically assigned based on each member\'s onboarding journey. They cannot be shared manually.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: Text(
                    'Understood',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.surface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show share sheet for public/discover groups.
  /// Loads real borough members from Firestore.
  void _showShareGroupSheet() {
    final onboarding = OnboardingDataService();
    final borough = PostcodeService().getBoroughFromPostcode(onboarding.postcode) ?? '';
    final userService = HuddlUserService();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: FutureBuilder<List<HuddlUser>>(
            future: userService.getBoroughMembers(borough),
            builder: (context, snapshot) {
              final members = (snapshot.data ?? [])
                  .where((u) => u.uid != currentUid)
                  .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: context.hc.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(Icons.share, color: HuddlColors.primary, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Share with members',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Share this group with members in your borough',
                      style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: context.hc.divider),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: HuddlColors.primary),
                    )
                  else if (members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No other members in $borough yet',
                        style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: members.length,
                        itemBuilder: (_, i) {
                          final member = members[i];
                          return ListTile(
                            leading: member.photoUrl.isNotEmpty
                                ? CircleAvatar(
                                    radius: 22,
                                    backgroundImage: NetworkImage(member.photoUrl),
                                  )
                                : CircleAvatar(
                                    radius: 22,
                                    backgroundColor: HuddlColors.peachLight,
                                    child: Text(
                                      member.name.isNotEmpty ? member.name[0] : '?',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.primary,
                                      ),
                                    ),
                                  ),
                            title: Text(
                              member.name,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              member.parentType == 'mum' ? 'Mum' : 'Dad',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: context.hc.textTertiary,
                              ),
                            ),
                            trailing: const Icon(Icons.send, size: 20, color: HuddlColors.primary),
                            onTap: () {
                              Navigator.pop(c);
                              _validateAndShareWith(
                                memberName: member.name,
                                memberParentType: member.parentType,
                                memberStages: member.stagesOfLife,
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Validate the target member fits the group's target audience before sharing.
  void _validateAndShareWith({
    required String memberName,
    required String memberParentType,
    required List<String> memberStages,
  }) {
    final audience = widget.targetAudience;

    // If no target audience restrictions, share freely
    if (audience.isEmpty) {
      _confirmShareSuccess(memberName);
      return;
    }

    // Check each audience restriction
    for (final label in audience) {
      switch (label) {
        case 'Mums':
          if (memberParentType != 'mum') {
            _showProfileMismatchDialog(memberName, label);
            return;
          }
        case 'Dads':
          if (memberParentType != 'dad') {
            _showProfileMismatchDialog(memberName, label);
            return;
          }
        case 'Parents expecting a baby':
          if (!memberStages.contains('expecting')) {
            _showProfileMismatchDialog(memberName, label);
            return;
          }
        case 'Aspiring parents':
          if (!memberStages.contains('aspiring')) {
            _showProfileMismatchDialog(memberName, label);
            return;
          }
      }
    }

    // All checks passed
    _confirmShareSuccess(memberName);
  }

  void _showProfileMismatchDialog(String memberName, String requiredProfile) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_off_outlined, size: 32, color: HuddlColors.primary),
              ),
              const SizedBox(height: 18),
              Text(
                'Cannot share with $memberName',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'This group is set up for "$requiredProfile" profiles. $memberName does not match this parent profile and cannot be added to the group.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.surface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmShareSuccess(String memberName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Group shared with $memberName!'),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Navigate to Saved messages screen filtered by this group ─────────────
  void _navigateToSavedForGroup() {
    Navigator.pushNamed(context, '/saved_messages_for_group', arguments: {
      'groupId': widget.groupId,
      'groupName': widget.groupName,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: _isSearching ? _buildSearchAppBar() : _buildAppBar(context),
      body: Column(
        children: [
          // Search results indicator
          if (_isSearching && _searchQuery.isNotEmpty)
            Container(
              color: HuddlColors.peachLight,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    _searchMatches.isEmpty
                        ? 'No results'
                        : '${_currentMatchIndex + 1} of ${_searchMatches.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_searchMatches.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      onPressed: _prevMatch,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      onPressed: _nextMatch,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ],
              ),
            ),

          // ── Messages list ─────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: HuddlColors.primary))
                : (_messages.isEmpty && _imageMessages.isEmpty)
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        // +1 extra slot at the end for flow poll cards
                        itemCount: _groupSortedItems.length +
                            (_flowPolls.isNotEmpty ? 1 : 0),
                        itemBuilder: (context, index) {
                          final items = _groupSortedItems;
                          // Last slot: render flow poll cards inside the
                          // scroll list so they scroll with messages and
                          // don't create a sticky block above the input bar.
                          if (index == items.length && _flowPolls.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Column(
                                children: _flowPolls.map((poll) => PollCard(
                                  poll: poll,
                                  onSelectOption: poll.isExpired
                                      ? null
                                      : (i) => _votePoll(poll.id, i),
                                  onViewDetails: poll.isCreatedByMe
                                      ? () => _viewPollDetails(poll)
                                      : null,
                                  onTogglePin: poll.isCreatedByMe
                                      ? () => _togglePollPin(poll.id)
                                      : null,
                                  onDeletePoll: poll.isCreatedByMe
                                      ? () => _deletePoll(poll.id)
                                      : null,
                                  onSeeResults: poll.isCreatedByMe
                                      ? () => _viewPollDetails(poll)
                                      : null,
                                  onChangeVote: !poll.isCreatedByMe && poll.hasVoted
                                      ? () => _showActivePollsSheet()
                                      : null,
                                )).toList(),
                              ),
                            );
                          }
                          if (index >= items.length) return const SizedBox.shrink();
                          final item = items[index];

                          // Image / location message
                          if (item.type == _GChatItemType.image) {
                            final imgMsg = _imageMessages[item.imageIndex!];
                            if (imgMsg.isLocationPin) {
                              return _GroupLocationBubble(
                                isMe: imgMsg.isMe,
                                timestamp: imgMsg.timestamp,
                                senderName: imgMsg.senderName,
                                senderAvatar: imgMsg.senderAvatar,
                                senderId: imgMsg.senderId,
                                locationName: imgMsg.locationLabel,
                                latitude: imgMsg.latitude,
                                longitude: imgMsg.longitude,
                              );
                            }
                            return _GroupImageBubble(
                              imageUrl: imgMsg.imageUrl,
                              isMe: imgMsg.isMe,
                              timestamp: imgMsg.timestamp,
                              senderName: imgMsg.senderName,
                              senderAvatar: imgMsg.senderAvatar,
                              senderId: imgMsg.senderId,
                              bytes: imgMsg.bytes,
                              onForward: () {
                                showForwardSheet(
                                  context: context,
                                  messageText: 'Photo',
                                  imageUrl: imgMsg.imageUrl,
                                  imageBytes: imgMsg.bytes,
                                );
                              },
                            );
                          }

                          // Document message
                          if (item.type == _GChatItemType.document) {
                            final docMsg = _documentMessages[item.docIndex!];
                            return Padding(
                              padding: EdgeInsets.only(
                                top: 4, bottom: 4,
                                left: docMsg.isMe ? 60 : 48, right: docMsg.isMe ? 0 : 60,
                              ),
                              child: Align(
                                alignment: docMsg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: DocumentBubble(
                                  fileName: docMsg.fileName,
                                  fileSize: docMsg.fileSize,
                                  isMe: docMsg.isMe,
                                  timestamp: docMsg.timestamp,
                                  onTap: docMsg.fileUrl.isNotEmpty
                                      ? () async {
                                          final uri = Uri.parse(docMsg.fileUrl);
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(
                                              uri,
                                              mode: LaunchMode.externalApplication,
                                            );
                                          } else if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Could not open document'),
                                              ),
                                            );
                                          }
                                        }
                                      : null,
                                  onForward: () {
                                    showForwardSheet(
                                      context: context,
                                      messageText: docMsg.fileName,
                                      documentName: docMsg.fileName,
                                    );
                                  },
                                ),
                              ),
                            );
                          }

                          final msgIdx = item.textIndex!;
                          if (msgIdx < 0 || msgIdx >= _messages.length) {
                            return const SizedBox.shrink();
                          }
                          final msg = _messages[msgIdx];

                          // Skip messages unsent "just for me"
                          if (_hiddenMessageIds.contains(msg.id)) {
                            return const SizedBox.shrink();
                          }

                          // Hide messages from blocked users
                          if (!msg.isMe && !msg.isSystem && _blockService.isUserBlocked(msg.senderId)) {
                            return const SizedBox.shrink();
                          }

                          // System messages (join/leave)
                          if (msg.isSystem) {
                            return _SystemMessageBubble(message: msg);
                          }

                          // Meetup invite card messages
                          // Render meetup card
                          if (msg.isMeetupCard && msg.meetupData != null) {
                            final showTimestampCard = msgIdx == 0 ||
                                msg.timestamp
                                        .difference(_messages[msgIdx - 1].timestamp)
                                        .inMinutes >
                                    5;
                            return Column(
                              children: [
                                if (showTimestampCard)
                                  _TimestampDivider(timestamp: msg.timestamp),
                                MeetupInviteCard(
                                  meetupData: msg.meetupData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Render group card
                          if (msg.isGroupCard && msg.groupData != null) {
                            final showTimestampCard = msgIdx == 0 ||
                                msg.timestamp
                                        .difference(_messages[msgIdx - 1].timestamp)
                                        .inMinutes >
                                    5;
                            return Column(
                              children: [
                                if (showTimestampCard)
                                  _TimestampDivider(timestamp: msg.timestamp),
                                GroupInviteCard(
                                  groupData: msg.groupData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Render item card
                          if (msg.isItemCard && msg.itemData != null) {
                            final showTimestampCard = msgIdx == 0 ||
                                msg.timestamp
                                        .difference(_messages[msgIdx - 1].timestamp)
                                        .inMinutes >
                                    5;
                            return Column(
                              children: [
                                if (showTimestampCard)
                                  _TimestampDivider(timestamp: msg.timestamp),
                                ItemInviteCard(
                                  itemData: msg.itemData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Render event card
                          if (msg.isEventCard && msg.eventData != null) {
                            final showTimestampCard = msgIdx == 0 ||
                                msg.timestamp
                                        .difference(_messages[msgIdx - 1].timestamp)
                                        .inMinutes >
                                    5;
                            return Column(
                              children: [
                                if (showTimestampCard)
                                  _TimestampDivider(timestamp: msg.timestamp),
                                EventInviteCard(
                                  eventData: msg.eventData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Voice note message
                          if (msg.isVoiceNote && msg.audioUrl != null) {
                            final showTsVoice = msgIdx == 0 ||
                                msg.timestamp
                                        .difference(_messages[msgIdx - 1].timestamp)
                                        .inMinutes >
                                    5;
                            return Column(
                              children: [
                                if (showTsVoice)
                                  _TimestampDivider(timestamp: msg.timestamp),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: 4, bottom: 4,
                                    left: msg.isMe ? 60 : 8,
                                    right: msg.isMe ? 8 : 60,
                                  ),
                                  child: Align(
                                    alignment: msg.isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: VoiceMessageBubble(
                                      audioUrl: msg.audioUrl!,
                                      durationSeconds: msg.audioDuration ?? 0,
                                      isMe: msg.isMe,
                                      timestamp: msg.timestamp,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          final showAvatar = msgIdx == 0 ||
                              _messages[msgIdx - 1].senderId != msg.senderId ||
                              _messages[msgIdx - 1].isSystem;
                          final showTimestamp = msgIdx == 0 ||
                              msg.timestamp
                                      .difference(_messages[msgIdx - 1].timestamp)
                                      .inMinutes >
                                  5;

                          final isHighlighted = _isSearching &&
                              _searchMatches.isNotEmpty &&
                              _currentMatchIndex >= 0 &&
                              _searchMatches[_currentMatchIndex] == msgIdx;

                          // Check if unsent for everyone
                          final isDeletedForEveryone = _deletedForEveryoneIds.contains(msg.id);

                          return Column(
                            children: [
                              if (showTimestamp)
                                _TimestampDivider(timestamp: msg.timestamp),
                              if (isDeletedForEveryone)
                                _GroupDeletedMessageBubble(
                                  isMe: msg.isMe,
                                  timestamp: msg.timestamp,
                                )
                              else
                                _ChatBubble(
                                  message: msg,
                                  showAvatar: showAvatar,
                                  messageStatus: _messageStatuses[msg.id],
                                  isHighlighted: isHighlighted,
                                  searchQuery: _searchQuery,
                                  isSaved: _savedMessageService.isMessageSaved(msg.id),
                                  onAvatarTap: msg.isMe
                                      ? null
                                      : () => _openDMWithMember(
                                            msg.senderId,
                                            msg.senderName,
                                            msg.senderAvatar,
                                          ),
                                  onSave: () {
                                    // Always show the topic-save dialog so any message
                                    // can be filed under a named topic.
                                    _showSaveThreadDialog(msg);
                                  },
                                  onForward: () {
                                    showForwardSheet(
                                      context: context,
                                      messageText: msg.message,
                                    );
                                  },
                                  onReact: () => _showEmojiPicker(msg.id),
                                  reactions: _reactions[msg.id] ?? {},
                                  onTapReaction: (emoji) => _toggleReaction(msg.id, emoji),
                                  onReply: () => _openThread(msg),
                                  onCopy: () => _copyMessage(msg.message),
                                  onUnsend: msg.isMe ? () => _showUnsendDialog(msg) : null,
                                  onSaveThread: (_threadReplies[msg.id] != null && _threadReplies[msg.id]!.isNotEmpty)
                                      ? () => _showSaveThreadDialog(msg)
                                      : null,
                                  onBlockUser: (!msg.isMe && msg.senderId != 'system')
                                      ? () => _showBlockMemberDialog(msg.senderId, msg.senderName)
                                      : null,
                                  isBlockedUser: !msg.isMe && _blockService.isUserBlocked(msg.senderId),
                                  onReportUser: (!msg.isMe && msg.senderId != 'system')
                                      ? () => _showReportMessageDialog(msg.id, msg.senderId, msg.senderName)
                                      : null,
                                  onReportSender: (!msg.isMe && msg.senderId != 'system')
                                      ? () => _showReportUserDialog(msg.senderId, msg.senderName)
                                      : null,
                                ),
                              // ── Thread reply count badge ────────────────
                              if (_threadReplies.containsKey(msg.id) && _threadReplies[msg.id]!.isNotEmpty)
                                GestureDetector(
                                  onTap: () => _openThread(msg),
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: msg.isMe ? 60 : 40,
                                      right: msg.isMe ? 0 : 60,
                                      top: 2,
                                      bottom: 4,
                                    ),
                                    child: Align(
                                      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: HuddlColors.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.forum_outlined, size: 13, color: HuddlColors.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${_threadReplies[msg.id]!.length} ${_threadReplies[msg.id]!.length == 1 ? 'reply' : 'replies'}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: HuddlColors.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.chevron_right, size: 14, color: HuddlColors.primary),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),

          // ── Pinned poll cards (always visible at top of chat) ──────
          if (_pinnedPolls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _pinnedPolls.map((poll) => PollCard(
                  poll: poll,
                  onSelectOption: poll.isExpired
                      ? null
                      : (i) => _votePoll(poll.id, i),
                  onViewDetails: poll.isCreatedByMe
                      ? () => _viewPollDetails(poll)
                      : null,
                  onTogglePin: poll.isCreatedByMe
                      ? () => _togglePollPin(poll.id)
                      : null,
                  onDeletePoll: poll.isCreatedByMe
                      ? () => _deletePoll(poll.id)
                      : null,
                  onSeeResults: poll.isCreatedByMe
                      ? () => _viewPollDetails(poll)
                      : null,
                  onChangeVote: !poll.isCreatedByMe && poll.hasVoted
                      ? () => _showActivePollsSheet()
                      : null,
                )).toList(),
              ),
            ),

          // ── Input bar ─────────────────────────────────────────────
          // Note: flow poll cards are now rendered inside the ListView
          // (as the last item) so they scroll with messages and the
          // input bar always sits at the very bottom.
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: HuddlColors.white,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchMatches = [];
            _currentMatchIndex = -1;
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search messages...',
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: _performGroupSearch,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: context.hc.divider),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: HuddlColors.white,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: GestureDetector(
        onTap: () {
          Navigator.pushNamed(context, '/group_details', arguments: {
            'groupId': widget.groupId,
            'groupName': widget.groupName,
            'groupImageUrl': widget.groupImageUrl,
            'isPrivate': widget.isPrivate,
            'creatorId': widget.creatorId,
            'creatorBorough': widget.creatorBorough,
          });
        },
        child: Row(
          children: [
            _buildGroupAvatar(32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Tap here for group info',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: context.hc.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: context.hc.textPrimary),
          onPressed: () => setState(() => _isSearching = true),
        ),
        // 3-dot popup menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.hc.textPrimary),
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: context.hc.surface,
          elevation: 8,
          onSelected: (value) {
            switch (value) {
              case 'active_polls':
                _showActivePollsSheet();
                break;
              case 'share':
                _handleShareGroup();
                break;
              case 'details':
                Navigator.pushNamed(context, '/group_details', arguments: {
                  'groupId': widget.groupId,
                  'groupName': widget.groupName,
                  'groupImageUrl': widget.groupImageUrl,
                  'isPrivate': widget.isPrivate,
                  'creatorId': widget.creatorId,
                  'creatorBorough': widget.creatorBorough,
                });
                break;
              case 'saved':
                _navigateToSavedForGroup();
                break;
              case 'saved_threads':
                _showSavedThreadsForGroup();
                break;
              case 'add_member':
                _showAddMemberSheet();
                break;
              case 'remove_member':
                _showRemoveMemberSheet();
                break;
              case 'add_admin':
                _showAddAdminSheet();
                break;
              case 'leave':
                _showLeaveGroupDialog();
                break;
            }
          },
          itemBuilder: (context) => [
            // Active Polls (always visible — badge shows count)
            PopupMenuItem<String>(
              value: 'active_polls',
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.poll_outlined,
                          size: 20, color: HuddlColors.primary),
                      if (_activePollCount > 0)
                        Positioned(
                          top: -5,
                          right: -6,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: HuddlColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$_activePollCount',
                                style: GoogleFonts.poppins(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: HuddlColors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Active Polls',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.primary,
                    ),
                  ),
                  if (_activePollCount > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_activePollCount active',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Divider before other items
            const PopupMenuDivider(),
            // Share group — hidden for default/onboarding groups which are
            // automatically assigned and cannot be shared or joined manually.
            if (!widget.isDefaultGroup)
            PopupMenuItem<String>(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share_outlined, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(
                    'Share group',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Group details
            PopupMenuItem<String>(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(
                    'Group details',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Saved messages
            PopupMenuItem<String>(
              value: 'saved',
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(
                    'Saved messages',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Saved threads
            PopupMenuItem<String>(
              value: 'saved_threads',
              child: Row(
                children: [
                  const Icon(Icons.topic_outlined, size: 20, color: HuddlColors.blue),
                  const SizedBox(width: 12),
                  Text(
                    'Saved threads',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // ── Private group admin actions ──────────────────────────
            if (widget.isPrivate && _isCreatorOrAdmin)
              PopupMenuItem<String>(
                value: 'add_member',
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, size: 20, color: context.hc.textPrimary),
                    const SizedBox(width: 12),
                    Text(
                      'Add member',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.hc.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.isPrivate && _isCreatorOrAdmin)
              PopupMenuItem<String>(
                value: 'remove_member',
                child: Row(
                  children: [
                    const Icon(Icons.person_remove_outlined, size: 20, color: HuddlColors.error),
                    const SizedBox(width: 12),
                    Text(
                      'Remove member',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.isPrivate && _isCreatorOrAdmin)
              PopupMenuItem<String>(
                value: 'add_admin',
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 20, color: HuddlColors.blue),
                    const SizedBox(width: 12),
                    Text(
                      'Add admin',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            // Leave group — only shown if eligible
            if (_canLeaveGroup)
              PopupMenuItem<String>(
                value: 'leave',
                child: Row(
                  children: [
                    const Icon(Icons.exit_to_app, size: 20, color: HuddlColors.error),
                    const SizedBox(width: 12),
                    Text(
                      'Leave group',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.error,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: context.hc.divider),
      ),
    );
  }

  Widget _buildGroupAvatar(double size) {
    final url = _liveGroupImageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: HuddlColors.peachLight,
      ),
      clipBehavior: Clip.antiAlias,
      child: url.startsWith('assets/')
          ? Image.asset(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.people,
                  size: size * 0.5, color: HuddlColors.primary),
            )
          : url.startsWith('http')
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.people,
                      size: size * 0.5, color: HuddlColors.primary),
                )
              : url.startsWith('data:')
                  ? _buildDataImage(size)
                  : Icon(Icons.people, size: size * 0.5, color: HuddlColors.primary),
    );
  }

  Widget _buildDataImage(double size) {
    try {
      final dataUri = Uri.parse(widget.groupImageUrl);
      final bytes = dataUri.data?.contentAsBytes();
      if (bytes != null) {
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.people,
              size: size * 0.5, color: HuddlColors.primary),
        );
      }
    } catch (_) {
      // fall through
    }
    return Icon(Icons.people, size: size * 0.5, color: HuddlColors.primary);
  }

  Widget _buildInputBar() {
    // ── Voice recording mode ────────────────────────────────────────────────
    if (_isVoiceRecording) {
      // Ensure keyboard is fully dismissed when recording UI shows
      FocusScope.of(context).unfocus();
      return VoiceRecordingIndicator(
        onCancel: () async {
          await _voiceSvc.cancelRecording();
          if (mounted) setState(() => _isVoiceRecording = false);
        },
        onSend: _sendVoiceMessage,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main input row ──────────────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
              8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: context.hc.surface,
            border: Border(top: BorderSide(color: context.hc.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: HuddlColors.primary,
                ),
                onPressed: _openAttachSheet,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.hc.scaffold,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    textAlignVertical: TextAlignVertical.center,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle:
                          GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Send when text exists; mic (hold to record) when empty
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  if (hasText) {
                    return GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          gradient: HuddlColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, size: 18, color: HuddlColors.white),
                      ),
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (_) async {
                      // Dismiss keyboard FIRST so iOS doesn't swallow the gesture
                      FocusScope.of(context).unfocus();
                      await Future.delayed(const Duration(milliseconds: 80));
                      if (!mounted) return;
                      final hasPerms = await _voiceSvc.hasPermission();
                      if (!hasPerms) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Microphone permission required.")),
                          );
                        }
                        return;
                      }
                      HapticFeedback.mediumImpact();
                      await _voiceSvc.startRecording();
                      if (mounted) setState(() => _isVoiceRecording = true);
                    },
                    onLongPressEnd: (_) async {
                      if (_isVoiceRecording) await _sendVoiceMessage();
                    },
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hold to record a voice message'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            gradient: HuddlColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mic, size: 22, color: HuddlColors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Send voice message ────────────────────────────────────────────────────
  Future<void> _sendVoiceMessage() async {
    final result = await _voiceSvc.stopRecording();
    if (mounted) setState(() => _isVoiceRecording = false);
    if (result == null || result.duration < 1) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'local';
      final audioUrl = await _voiceSvc.uploadVoiceNote(
        result.path,
        conversationId: widget.groupId,
      );
      final me = _onboardingService.name ?? 'You';
      final ts = DateTime.now();
      final optimisticMsg = ChatMessage(
        id: 'vm_${ts.millisecondsSinceEpoch}',
        senderId: uid,
        senderName: me,
        senderAvatar: _myPhotoUrl,
        message: '🎤 Voice message',
        timestamp: ts,
        isMe: true,
        isVoiceNote: true,
        audioUrl: audioUrl,
        audioDuration: result.duration,
      );
      setState(() => _messages.insert(0, optimisticMsg));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: '🎤 Voice message',
        audioUrl: audioUrl,
        audioDuration: result.duration,
        type: 'voice_note',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    }
  }

  // _buildAttachOption removed — replaced by WhatsApp-style attach_bottom_sheet.dart

  // ── Create poll flow ──────────────────────────────────────────────────
  Future<void> _openCreatePoll() async {
    final result = await Navigator.push<PollData>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePollScreen(groupName: widget.groupName),
      ),
    );
    if (result == null || !mounted) return;

    final userName = _onboardingService.name ?? 'You';
    final newPoll = ActivePoll(
      id: 'poll_${DateTime.now().millisecondsSinceEpoch}',
      data: result,
      creatorName: userName,
      creatorId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
      createdAt: DateTime.now(),
      isPinned: false,
    );

    // Persist to PollService FIRST so the list is ready before setState
    await _pollService.addPoll(widget.groupId, newPoll);

    if (!mounted) return;
    setState(() {
      // Add a system message about the poll
      _messages.add(ChatMessage(
        id: 'sys_poll_${DateTime.now().millisecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'System',
        senderAvatar: '',
        message: '$userName created a poll: "${result.question}"',
        timestamp: DateTime.now(),
        isMe: false,
        isSystem: true,
      ));
    });

    // ── Write to Firestore so other devices see and can vote on the poll ──
    try {
      await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: '\u{1F4CA} Poll: "${result.question}"',
        type: 'poll',
        pollQuestion: result.question,
        pollOptions: result.options,
        pollAllowMultiple: result.allowMultiple,
        pollIsCalendarMode: result.isCalendarMode,
        pollExpiresAt: result.expiresAt?.toIso8601String(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Poll Firestore write error: $e');
    }

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _votePoll(String pollId, int optionIndex) {
    setState(() {
      final idx = _polls.indexWhere((p) => p.id == pollId);
      if (idx == -1) return;
      final poll = _polls[idx];
      if (poll.isExpired) return;

      final userName = _onboardingService.name ?? 'You';

      if (poll.data.allowMultiple) {
        // Toggle vote for multi-choice polls
        if (poll.myVotes.contains(optionIndex)) {
          poll.myVotes.remove(optionIndex);
          poll.votes.removeWhere(
            (v) => v.memberId == 'current_user' && v.optionIndex == optionIndex,
          );
        } else {
          poll.myVotes.add(optionIndex);
          poll.votes.add(PollVote(
            memberId: 'current_user',
            memberName: userName,
            optionIndex: optionIndex,
          ));
        }
      } else {
        // Single-choice: swap selection (allow change of vote)
        poll.votes.removeWhere((v) => v.memberId == 'current_user');
        poll.myVotes.clear();
        poll.myVotes.add(optionIndex);
        poll.votes.add(PollVote(
          memberId: 'current_user',
          memberName: userName,
          optionIndex: optionIndex,
        ));
      }
    });

    // Persist vote changes
    _pollService.savePolls(widget.groupId, List.from(_polls));

    // If anyone (creator or member) just voted on an unpinned poll → show hint
    final poll = _polls.firstWhere((p) => p.id == pollId);
    if (!poll.isPinned && poll.hasVoted) {
      final msg = poll.isCreatedByMe
          ? 'Vote recorded. View results via ⋮ → Active Polls.'
          : 'Vote recorded. Access via ⋮ → Active Polls to change.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: HuddlColors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg,
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View',
            textColor: HuddlColors.white,
            onPressed: _showActivePollsSheet,
          ),
        ),
      );
    }
  }

  void _togglePollPin(String pollId) {
    setState(() {
      final idx = _polls.indexWhere((p) => p.id == pollId);
      if (idx == -1) return;
      _polls[idx].isPinned = !_polls[idx].isPinned;
    });
    // Persist pin change
    _pollService.savePolls(widget.groupId, List.from(_polls));
  }

  void _deletePoll(String pollId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Poll',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete this poll? All votes will be lost and no users will be able to see or update the poll.',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: context.hc.textTertiary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                final idx = _polls.indexWhere((p) => p.id == pollId);
                if (idx != -1) {
                  _polls[idx].isDeleted = true;
                }
              });
              // Persist deletion
              _pollService.savePolls(widget.groupId, List.from(_polls));
            },
            child: Text('Delete',
                style: GoogleFonts.poppins(
                    color: HuddlColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Opens the Active Polls sheet — the hub for all polls in this group.
  /// Non-creators can change their vote here; creators can see results.
  void _showActivePollsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ActivePollsSheet(
        polls: _polls,
        onVote: (pollId, optionIndex) {
          _votePoll(pollId, optionIndex);
        },
        onViewDetails: (poll) => _viewPollDetails(poll),
        onTogglePin: (pollId) {
          setState(() => _togglePollPin(pollId));
        },
        onDeletePoll: (pollId) => _deletePoll(pollId),
      ),
    );
  }

  void _viewPollDetails(ActivePoll poll) {
    // Only the creator can view full results
    if (!poll.isCreatedByMe) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PollDetailScreen(
          poll: poll,
          onDeletePoll: () => _deletePoll(poll.id),
        ),
      ),
    );
  }

  // ── Media permission prompt ────────────────────────────────────────────
  // ── Interleaved list helpers ────────────────────────────────────────
  List<_GChatItem> get _groupSortedItems {
    final items = <_GChatItem>[];
    for (int i = 0; i < _messages.length; i++) {
      items.add(_GChatItem(type: _GChatItemType.text, textIndex: i, timestamp: _messages[i].timestamp));
    }
    for (int i = 0; i < _imageMessages.length; i++) {
      items.add(_GChatItem(type: _GChatItemType.image, imageIndex: i, timestamp: _imageMessages[i].timestamp));
    }
    for (int i = 0; i < _documentMessages.length; i++) {
      items.add(_GChatItem(type: _GChatItemType.document, docIndex: i, timestamp: _documentMessages[i].timestamp));
    }
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return items;
  }

  // ── WhatsApp-style attach handler (group has Poll option too) ───────
  Future<void> _openAttachSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _GroupAttachSheet(),
    );
    if (result == null || !mounted) return;

    switch (result) {
      case 'camera':
        await _handleCameraCapture();
        break;
      case 'gallery':
        await _handleGalleryPick();
        break;
      case 'document':
        await _handleDocumentPick();
        break;
      case 'location':
        _handleLocationShare();
        break;
      case 'contact':
        _handleContactShare();
        break;
      case 'poll':
        _openCreatePoll();
        break;
    }
  }

  Future<void> _handleCameraCapture() async {
    final attachment = await _mediaService.takePhoto();
    if (attachment == null || !mounted) return;
    await _addImageMessage(attachment);
  }

  Future<void> _handleGalleryPick() async {
    final attachments = await _mediaService.pickMultipleImages();
    if (attachments.isEmpty || !mounted) return;
    for (final att in attachments) {
      await _addImageMessage(att);
    }
  }

  Future<void> _addImageMessage(MediaAttachment att) async {
    final userName = _onboardingService.name ?? 'You';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Use a stable placeholder key so we can patch it with the real https URL
    // after upload.  The key must never match a real Firebase Storage URL so
    // the deduplication guard in the Firestore stream doesn't eat the update.
    final optimisticKey = 'local_pending_${currentUid}_$ts';

    // Optimistic local add — visible immediately to sender
    setState(() {
      _imageMessages.add(_GroupImageMessage(
        imageUrl: optimisticKey,
        isMe: true,
        timestamp: DateTime.now(),
        senderName: userName,
        senderAvatar: '#FF975C',
        senderId: currentUid,
        bytes: att.bytes,
      ));
    });
    await _persistUserMediaMessages();
    _fireMessageSentNotifier();
    _scrollToEnd();

    // Upload to Firebase Storage and write to Firestore so other devices see the photo
    try {
      final storageRef = FirebaseStorage.instance
          .ref('group_images/${widget.groupId}/${currentUid}_$ts.jpg');

      TaskSnapshot snap;
      if (att.bytes != null) {
        snap = await storageRef.putData(
          att.bytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else if (att.filePath != null && !kIsWeb) {
        // Native platforms — upload from file path
        snap = await storageRef.putFile(File(att.filePath!));
      } else {
        // No uploadable data — skip Firestore write
        return;
      }

      final downloadUrl = await snap.ref.getDownloadURL();

      // ── Patch the optimistic entry with the real https URL ───────────────
      // This ensures:
      //   (a) The sender's image widget switches from bytes→url rendering,
      //       consistent with what other devices receive.
      //   (b) The Firestore stream deduplication (imageUrl match) works on
      //       restart — the stored URL now equals what Firestore has.
      if (mounted) {
        setState(() {
          final idx = _imageMessages
              .indexWhere((m) => m.imageUrl == optimisticKey);
          if (idx >= 0) {
            final old = _imageMessages[idx];
            _imageMessages[idx] = _GroupImageMessage(
              imageUrl: downloadUrl,
              isMe: old.isMe,
              timestamp: old.timestamp,
              senderName: old.senderName,
              senderAvatar: old.senderAvatar,
              senderId: old.senderId,
              bytes: old.bytes, // keep bytes so image stays sharp locally
            );
          }
        });
        // Re-persist with the real URL so BrowserStorage cache is consistent
        await _persistUserMediaMessages();
      }

      // Register the real Firestore URL as a known ID so the stream listener
      // doesn't add it again as a duplicate when the echo comes back.
      _firestoreMsgIds.add('img_$downloadUrl');

      await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: '📷 Photo',
        type: 'image',
        imageUrl: downloadUrl,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Image upload/Firestore error: $e');
      // Sender already sees the image locally — non-fatal, no UI disruption needed
    }
  }

  Future<void> _handleDocumentPick() async {
    final attachment = await _mediaService.pickDocument();
    if (attachment == null || !mounted) return;
    final userName = _onboardingService.name ?? 'You';
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final docName = attachment.fileName ?? 'Document';
    final ts = DateTime.now();
    setState(() {
      _documentMessages.add(_GroupDocumentMessage(
        fileName: docName,
        fileSize: attachment.fileSize,
        fileUrl: '',          // will be updated after upload
        isMe: true,
        timestamp: ts,
        senderName: userName,
        senderAvatar: '#FF975C',
        senderId: currentUid,
      ));
    });
    await _persistUserMediaMessages();
    _fireMessageSentNotifier();
    _scrollToEnd();

    // ── Upload to Firebase Storage and write to Firestore ───────────────
    // Other devices will see the document via the stream / history load.
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final epoch = ts.millisecondsSinceEpoch;
      final ext = docName.contains('.') ? docName.split('.').last : 'bin';
      final storageRef = FirebaseStorage.instance
          .ref('group_documents/${widget.groupId}/${uid}_$epoch.$ext');

      TaskSnapshot snap;
      if (attachment.bytes != null) {
        snap = await storageRef.putData(
          attachment.bytes!,
          SettableMetadata(contentType: attachment.mimeType ?? 'application/octet-stream'),
        );
      } else if (attachment.filePath != null && !kIsWeb) {
        snap = await storageRef.putFile(File(attachment.filePath!));
      } else {
        // No uploadable data — write metadata-only to Firestore so others
        // at least see the document name in the chat.
        await FirestoreService().sendGroupMessage(
          groupId: widget.groupId,
          message: '\u{1F4CE} $docName',
          type: 'document',
          documentName: docName,
          documentSize: attachment.fileSize,
        );
        return;
      }

      final downloadUrl = await snap.ref.getDownloadURL();
      await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: '\u{1F4CE} $docName',
        type: 'document',
        documentUrl: downloadUrl,
        documentName: docName,
        documentSize: attachment.fileSize,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Document upload/Firestore error: $e');
    }
  }

  Future<void> _handleLocationShare() async {
    if (!mounted) return;
    final userName = _onboardingService.name ?? 'You';

    // Show a "getting location…" snackbar while we wait
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Getting your location…', style: GoogleFonts.poppins(fontSize: 13)),
          ],
        ),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    double lat = 52.2053; // Cambridge fallback
    double lng = 0.1218;
    String label = 'My location';

    // Geolocation: web uses browser API via JS interop,
    // iOS/Android uses the Cambridge fallback (location_picker can be
    // added later via the geolocator package for native GPS support).
    if (kIsWeb) {
      try {
        // Web-only: use dart:html / js_interop at runtime via eval workaround
        // We keep this block web-guarded so it compiles on all platforms.
        await Future.delayed(const Duration(seconds: 1)); // placeholder
      } catch (_) {
        // Keep Cambridge fallback
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final msg = _GroupImageMessage(
      imageUrl: 'location_pin',
      isMe: true,
      timestamp: DateTime.now(),
      senderName: userName,
      senderAvatar: '#FF975C',
      senderId: currentUid,
      isLocationPin: true,
      latitude: lat,
      longitude: lng,
      locationLabel: label,
    );
    setState(() {
      _imageMessages.add(msg);
    });
    await _persistUserMediaMessages();
    _fireMessageSentNotifier();
    _scrollToEnd();

    // Write to Firestore so other devices see the location pin
    try {
      await FirestoreService().sendGroupMessage(
        groupId: widget.groupId,
        message: '📍 Location',
        type: 'location',
        latitude: lat,
        longitude: lng,
        locationLabel: label,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[GroupChat] Location Firestore write error: $e');
    }
  }

  void _handleContactShare() async {
    if (!mounted) return;
    final userName = _onboardingService.name ?? 'You';
    // Show a contact picker dialog
    final members = [
      {'name': 'Emma Wilson', 'phone': '+44 7700 900001'},
      {'name': 'Sophie Brown', 'phone': '+44 7700 900002'},
      {'name': 'James Taylor', 'phone': '+44 7700 900003'},
      {'name': 'Olivia Davis', 'phone': '+44 7700 900004'},
      {'name': 'Luke Harris', 'phone': '+44 7700 900005'},
      {'name': 'Anna Clark', 'phone': '+44 7700 900006'},
      {'name': 'Kate Miller', 'phone': '+44 7700 900007'},
    ];
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Share Contact', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
              const SizedBox(height: 8),
              ...members.map((m) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: HuddlColors.primary.withValues(alpha: 0.1),
                  child: Text(m['name']![0], style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                ),
                title: Text(m['name']!, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                subtitle: Text(m['phone']!, style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
                onTap: () => Navigator.pop(ctx, m),
              )),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
    if (result != null && mounted) {
      final contactName  = result['name']  ?? 'Unknown';
      final contactPhone = result['phone'] ?? '';
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      // Optimistic local add
      setState(() {
        _messages.add(ChatMessage(
          id: 'gm_contact_${DateTime.now().millisecondsSinceEpoch}',
          senderId: currentUid,
          senderName: userName,
          senderAvatar: '#FF975C',
          message: '\u{1F464} Contact: $contactName - $contactPhone',
          timestamp: DateTime.now(),
          isMe: true,
        ));
      });
      await _persistUserTextMessages();
      _fireMessageSentNotifier();
      _scrollToEnd();

      // ── Write to Firestore so all other devices see the contact card ──
      try {
        await FirestoreService().sendGroupMessage(
          groupId: widget.groupId,
          message: '\u{1F464} Contact: $contactName',
          type: 'contact',
          contactName: contactName,
          contactPhone: contactPhone,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[GroupChat] Contact Firestore write error: $e');
      }
    }
  }

  // ── Persistence for user-created messages in group chat ────────────────
  String get _userTextMsgKey => 'gc_user_texts_${widget.groupId}';
  String get _userMediaMsgKey => 'gc_user_media_${widget.groupId}';
  String get _userReactionsKey => 'gc_reactions_${widget.groupId}';

  /// Fires the messageSent notifier, always incrementing seq so the
  /// Messages-tab listener triggers even for back-to-back sends.
  void _fireMessageSentNotifier() {
    GroupChatScreen.messageSent.value = {
      'groupId': widget.groupId,
      'seq': (GroupChatScreen.messageSent.value['seq'] as int) + 1,
    };
  }

  Future<void> _persistUserTextMessages() async {
    try {
      final userMsgs = _messages
          .where((m) => m.isMe)
          .map((m) => {
                'id': m.id,
                'senderId': m.senderId,
                'senderName': m.senderName,
                'senderAvatar': m.senderAvatar,
                'message': m.message,
                'timestamp': m.timestamp.toIso8601String(),
                'isMe': true,
              })
          .toList();
      await BrowserStorage.setString(_userTextMsgKey, json.encode(userMsgs));
    } catch (_) {}
  }

  Future<void> _persistUserMediaMessages() async {
    try {
      final imgs = _imageMessages
          .where((m) => m.isMe)
          .map((m) => {
                'imageUrl': m.imageUrl,
                // Persist bytes as base64 so the image survives navigation/reload
                if (m.bytes != null) 'bytesBase64': base64Encode(m.bytes!),
                'isMe': true,
                'timestamp': m.timestamp.toIso8601String(),
                'senderName': m.senderName,
                'senderAvatar': m.senderAvatar,
                'senderId': m.senderId,
                'isLocationPin': m.isLocationPin,
              })
          .toList();
      final docs = _documentMessages
          .where((m) => m.isMe)
          .map((m) => {
                'fileName': m.fileName,
                'fileSize': m.fileSize,
                'fileUrl': m.fileUrl,
                'isMe': true,
                'timestamp': m.timestamp.toIso8601String(),
                'senderName': m.senderName,
                'senderAvatar': m.senderAvatar,
                'senderId': m.senderId,
              })
          .toList();
      await BrowserStorage.setString(
          _userMediaMsgKey, json.encode({'images': imgs, 'documents': docs}));
    } catch (_) {}
  }

  Future<void> _persistReactions() async {
    try {
      final data = <String, dynamic>{};
      _reactions.forEach((key, value) {
        data[key] = value;
      });
      await BrowserStorage.setString(_userReactionsKey, json.encode(data));
    } catch (_) {}
  }

  Future<void> _loadPersistedUserMessages() async {
    try {
      // Load user text messages
      final textRaw = await BrowserStorage.getString(_userTextMsgKey);
      if (textRaw != null) {
        final List<dynamic> decoded = json.decode(textRaw);
        for (final j in decoded) {
          final m = j as Map<String, dynamic>;
          final id = m['id'] as String;
          if (!_messages.any((msg) => msg.id == id)) {
            _messages.add(ChatMessage(
              id: id,
              senderId: m['senderId'] as String,
              senderName: m['senderName'] as String,
              senderAvatar: m['senderAvatar'] as String? ?? '#FF975C',
              message: m['message'] as String,
              timestamp: DateTime.parse(m['timestamp'] as String),
              isMe: true,
            ));
          }
        }
      }

      // Load user media messages
      final mediaRaw = await BrowserStorage.getString(_userMediaMsgKey);
      if (mediaRaw != null) {
        final Map<String, dynamic> decoded = json.decode(mediaRaw);
        final imgs = (decoded['images'] as List<dynamic>?) ?? [];
        for (final j in imgs) {
          final m = j as Map<String, dynamic>;
          // Restore bytes from persisted base64 (if present)
          Uint8List? restoredBytes;
          final b64 = m['bytesBase64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            try { restoredBytes = base64Decode(b64); } catch (_) {}
          }
          _imageMessages.add(_GroupImageMessage(
            imageUrl: m['imageUrl'] as String,
            bytes: restoredBytes,
            isMe: true,
            timestamp: DateTime.parse(m['timestamp'] as String),
            senderName: m['senderName'] as String,
            senderAvatar: m['senderAvatar'] as String? ?? '#FF975C',
            senderId: m['senderId'] as String,
            isLocationPin: m['isLocationPin'] as bool? ?? false,
          ));
        }
        final docs = (decoded['documents'] as List<dynamic>?) ?? [];
        for (final j in docs) {
          final m = j as Map<String, dynamic>;
          _documentMessages.add(_GroupDocumentMessage(
            fileName: m['fileName'] as String,
            fileSize: m['fileSize'] as int?,
            fileUrl: m['fileUrl'] as String? ?? '',
            isMe: true,
            timestamp: DateTime.parse(m['timestamp'] as String),
            senderName: m['senderName'] as String,
            senderAvatar: m['senderAvatar'] as String? ?? '#FF975C',
            senderId: m['senderId'] as String,
          ));
        }
      }

      // Load reactions
      final rxnRaw = await BrowserStorage.getString(_userReactionsKey);
      if (rxnRaw != null) {
        final Map<String, dynamic> decoded = json.decode(rxnRaw);
        decoded.forEach((key, value) {
          final rxnMap = <String, int>{};
          (value as Map<String, dynamic>).forEach((k, v) {
            rxnMap[k] = v as int;
          });
          _reactions[key] = rxnMap;
        });
      }
    } catch (_) {}
  }

  /// Load messages that were forwarded to this group via forward_message_sheet
  Future<void> _loadForwardedMessages() async {
    try {
      final key = 'group_messages_${widget.groupId}';
      final raw = await BrowserStorage.getString(key);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final m = j as Map<String, dynamic>;
          final id = m['id'] as String;
          if (!_messages.any((msg) => msg.id == id)) {
            final msgType = m['type'] as String? ?? 'text';
            if (msgType == 'image' && m['imageUrl'] != null) {
              // Restore bytes from base64 if the forward sheet persisted them
              Uint8List? restoredBytes;
              final b64 = m['bytesBase64'] as String?;
              if (b64 != null && b64.isNotEmpty) {
                try { restoredBytes = base64Decode(b64); } catch (_) {}
              }
              _imageMessages.add(_GroupImageMessage(
                imageUrl: m['imageUrl'] as String,
                bytes: restoredBytes,
                isMe: true,
                timestamp: DateTime.parse(m['timestamp'] as String),
                senderName: m['senderName'] as String? ?? 'You',
                senderAvatar: '#FF975C',
                senderId: 'current_user',
              ));
            } else if (msgType == 'location') {
              _imageMessages.add(_GroupImageMessage(
                imageUrl: 'location_pin',
                isMe: true,
                timestamp: DateTime.parse(m['timestamp'] as String),
                senderName: m['senderName'] as String? ?? 'You',
                senderAvatar: '#FF975C',
                senderId: 'current_user',
                isLocationPin: true,
              ));
            } else {
              // Safe cast helper to prevent type mismatch crashes
              Map<String, dynamic>? safeMap(dynamic raw) {
                if (raw == null) return null;
                if (raw is Map<String, dynamic>) return raw;
                if (raw is Map) return Map<String, dynamic>.from(raw);
                return null;
              }
              final rawMeetupData = safeMap(m['meetupData']);
              final rawGroupData  = safeMap(m['groupData']);
              final rawItemData   = safeMap(m['itemData']);
              final rawEventData  = safeMap(m['eventData']);
              _messages.add(ChatMessage(
                id: id,
                senderId: m['senderId'] as String? ?? 'current_user',
                senderName: m['senderName'] as String? ?? 'You',
                senderAvatar: '#FF975C',
                message: m['message'] as String? ?? '',
                timestamp: DateTime.parse(m['timestamp'] as String),
                isMe: true,
                isMeetupCard: (m['isMeetupCard'] as bool? ?? false) || rawMeetupData != null,
                meetupData: rawMeetupData,
                isGroupCard: (m['isGroupCard'] as bool? ?? false) || rawGroupData != null,
                groupData: rawGroupData,
                isItemCard: (m['isItemCard'] as bool? ?? false) || rawItemData != null,
                itemData: rawItemData,
                isEventCard: (m['isEventCard'] as bool? ?? false) || rawEventData != null,
                eventData: rawEventData,
              ));
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Load meetup notification posted by CreateMeetupScreen as a clickable meetup card
  Future<void> _loadMeetupNotification() async {
    try {
      final key = 'meetup_notification_${widget.groupId}';
      final raw = await BrowserStorage.getString(key);
      if (raw != null) {
        final Map<String, dynamic> data = json.decode(raw);
        final msgId = 'meetup_notif_${data['meetupId']}';
        if (!_messages.any((msg) => msg.id == msgId)) {
          final ts = DateTime.tryParse(data['timestamp'] as String? ?? '') ?? DateTime.now();
          final meetupData = data['meetupData'] as Map<String, dynamic>?;
          _messages.add(ChatMessage(
            id: msgId,
            senderId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
            senderName: data['organiser'] as String? ?? 'You',
            senderAvatar: '#FF975C',
            message: data['meetupTitle'] as String? ?? 'Meetup',
            timestamp: ts,
            isMe: true,
            isMeetupCard: meetupData != null,
            meetupData: meetupData,
          ));
        }
      }
    } catch (_) {}
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _emptyState() {
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
            child:
                const Icon(Icons.chat_bubble_outline, size: 36, color: HuddlColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello to the group!',
            style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
          ),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// SYSTEM MESSAGE BUBBLE — centered, styled differently from chat bubbles
// ═══════════════════════════════════════════════════════════════════════════════

class _SystemMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _SystemMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: context.hc.scaffold,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.hc.divider,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                message.message.contains('joined')
                    ? Icons.person_add_alt_1
                    : message.message.contains('left')
                        ? Icons.person_remove_alt_1
                        : Icons.info_outline,
                size: 14,
                color: message.message.contains('joined')
                    ? HuddlColors.teal
                    : HuddlColors.textHint,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  message.message,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: context.hc.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHAT BUBBLE — with long-press to save
// ═══════════════════════════════════════════════════════════════════════════════

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showAvatar;
  final MessageStatus? messageStatus;
  final bool isHighlighted;
  final String searchQuery;
  final bool isSaved;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onSave;
  final VoidCallback? onForward;
  final VoidCallback? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onUnsend;
  final VoidCallback? onSaveThread;
  final VoidCallback? onBlockUser;
  final bool isBlockedUser;
  final VoidCallback? onReportUser;
  final VoidCallback? onReportSender;
  final Map<String, int> reactions;
  final void Function(String emoji)? onTapReaction;

  const _ChatBubble({
    required this.message,
    required this.showAvatar,
    this.messageStatus,
    this.isHighlighted = false,
    this.searchQuery = '',
    this.isSaved = false,
    this.onAvatarTap,
    this.onSave,
    this.onForward,
    this.onReact,
    this.onReply,
    this.onCopy,
    this.onUnsend,
    this.onSaveThread,
    this.onBlockUser,
    this.isBlockedUser = false,
    this.onReportUser,
    this.onReportSender,
    this.reactions = const {},
    this.onTapReaction,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: () => _showMessageActions(context),
          onDoubleTap: onReact,
          child: Padding(
            padding: EdgeInsets.only(
              top: showAvatar ? 12 : 2,
              bottom: reactions.isEmpty ? 2 : 0,
              left: isMe ? 60 : 0,
              right: isMe ? 0 : 60,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe) ...[
                  if (showAvatar)
                    GestureDetector(
                      onTap: onAvatarTap,
                      child: _SenderAvatar(
                        colorHex: message.senderAvatar,
                        name: message.senderName,
                        senderId: message.senderId,
                        showTapHint: onAvatarTap != null,
                        // Pass the stored photo URL directly so real Firebase
                        // users always show their profile photo
                        photoUrl: message.senderAvatar.startsWith('http')
                            ? message.senderAvatar
                            : null,
                      ),
                    )
                  else
                    const SizedBox(width: 32),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment:
                        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (showAvatar && !isMe)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: GestureDetector(
                            onTap: onAvatarTap,
                            child: Text(
                              message.senderName,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _colorFromHex(message.senderAvatar),
                              ),
                            ),
                          ),
                        ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isHighlighted
                              ? HuddlColors.yellowBackground
                              : isMe
                                  ? _kMyBubble
                                  : HuddlColors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Message text (with search highlighting)
                            searchQuery.isNotEmpty
                                ? _buildHighlightedText(message.message, searchQuery, isMe: isMe)
                                : Text(
                                    message.message,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: context.hc.textPrimary,
                                      height: 1.4,
                                    ),
                                  ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSaved) ...[
                                  Icon(Icons.bookmark, size: 12,
                                      color: HuddlColors.primary.withValues(alpha: 0.6)),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  _formatTime(message.timestamp),
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: context.hc.textTertiary,
                                  ),
                                ),
                                if (isMe && messageStatus != null) ...[
                                  const SizedBox(width: 4),
                                  _GroupMessageStatusIcon(status: messageStatus!),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Emoji reactions row — sits in the outer Column, outside the
        // avatar Row, so it aligns flush with the bubble and is not
        // pushed down by the Row's crossAxisAlignment layout.
        if (reactions.isNotEmpty)
          EmojiReactionDisplay(
            reactions: reactions,
            isMe: isMe,
            onTapReaction: onTapReaction,
          ),
      ],
    );
  }

  void _showMessageActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              // Message preview
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.hc.scaffold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 16, color: context.hc.textTertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.message,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Quick emoji row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ...kQuickEmojis.map((emoji) => GestureDetector(
                      onTap: () {
                        Navigator.pop(c);
                        onTapReaction?.call(emoji);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                    )),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(c);
                        onReact?.call();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.hc.scaffold,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, color: context.hc.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.hc.divider),
              ListTile(
                leading: Icon(
                  isSaved ? Icons.bookmark : (onSaveThread != null ? Icons.bookmark_add_outlined : Icons.bookmark_outline),
                  color: isSaved ? HuddlColors.primary : context.hc.textPrimary,
                ),
                title: Text(
                  isSaved ? 'Unsave message' : (onSaveThread != null ? 'Save message & thread' : 'Save message'),
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(c);
                  onSave?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.copy_outlined, color: context.hc.textPrimary),
                title: Text('Copy text',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onCopy?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.forum_outlined, color: context.hc.textPrimary),
                title: Text('Reply in thread',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onReply?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.forward_outlined, color: context.hc.textPrimary),
                title: Text('Forward',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onForward?.call();
                },
              ),
              if (onUnsend != null)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: HuddlColors.error),
                  title: Text('Unsend message',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error)),
                  onTap: () {
                    Navigator.pop(c);
                    onUnsend?.call();
                  },
                ),
              if (onSaveThread != null)
                ListTile(
                  leading: const Icon(Icons.topic_outlined, color: HuddlColors.blue),
                  title: Text('Save reply thread',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(c);
                    onSaveThread?.call();
                  },
                ),
              if (onBlockUser != null)
                ListTile(
                  leading: Icon(
                    isBlockedUser ? Icons.check_circle_outline : Icons.block,
                    color: HuddlColors.error,
                  ),
                  title: Text(
                    isBlockedUser ? 'Unblock ${message.senderName}' : 'Block ${message.senderName}',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    onBlockUser?.call();
                  },
                ),
              if (onReportUser != null)
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: HuddlColors.error),
                  title: Text(
                    'Report message',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    onReportUser?.call();
                  },
                ),
              if (onReportSender != null)
                ListTile(
                  leading: const Icon(Icons.person_off_outlined, color: HuddlColors.error),
                  title: Text(
                    'Report ${message.senderName}',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    onReportSender?.call();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(String text, String query, {bool isMe = false}) {
    if (query.isEmpty) {
      return Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14, color: HuddlColors.textDark, height: 1.4));
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;
    while (true) {
      final idx = lower.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: TextStyle(
          // Sent (my) bubbles: deeper orange background highlight
          // Received bubbles: bold text with subtle background
          backgroundColor: isMe
              ? const Color(0xFFE8845A) // deeper coral for sent bubbles
              : const Color(0xFFFFF176), // light yellow for received bubbles
          fontWeight: FontWeight.w700,
          color: isMe ? Colors.white : HuddlColors.textDark,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
            fontSize: 14, color: HuddlColors.textDark, height: 1.4),
        children: spans,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Deleted message bubble — shown when message is unsent for everyone
class _GroupDeletedMessageBubble extends StatelessWidget {
  final bool isMe;
  final DateTime timestamp;

  const _GroupDeletedMessageBubble({
    required this.isMe,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 4, bottom: 4,
        left: isMe ? 60 : 48,
        right: isMe ? 0 : 60,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.hc.scaffold,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: Border.all(color: context.hc.divider, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 14, color: context.hc.textTertiary),
              const SizedBox(width: 6),
              Text(
                'This message was deleted',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: context.hc.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtTime(timestamp),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: context.hc.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Message status icon for group chat messages
class _GroupMessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _GroupMessageStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    // If the current user has read receipts disabled, cap display at "delivered".
    final effectiveStatus =
        (!UserPrivacyPrefsService().readReceipts &&
                status == MessageStatus.read)
            ? MessageStatus.delivered
            : status;

    switch (effectiveStatus) {
      case MessageStatus.sending:
        return Icon(Icons.access_time, size: 14, color: context.hc.textTertiary);
      case MessageStatus.sent:
        return Icon(Icons.check, size: 14, color: context.hc.textTertiary);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: context.hc.textTertiary);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: HuddlColors.blue);
      case MessageStatus.error:
        return const Icon(Icons.error_outline, size: 14, color: HuddlColors.error);
    }
  }
}

/// Per-session cache: senderId → parentType (kept for Firestore read consistency).
final Map<String, String> _senderParentTypeCache = {};

/// Per-session cache: senderId → real Firestore photoUrl ('' = no photo).
final Map<String, String> _senderPhotoCache = {};

class _SenderAvatar extends StatefulWidget {
  final String colorHex;
  final String name;
  final String? senderId;
  final bool showTapHint;

  /// Direct photo URL stored on the Firestore message — shown when non-empty.
  final String? photoUrl;

  const _SenderAvatar({
    required this.colorHex,
    required this.name,
    this.senderId,
    this.showTapHint = false,
    this.photoUrl,
  });

  @override
  State<_SenderAvatar> createState() => _SenderAvatarState();
}

class _SenderAvatarState extends State<_SenderAvatar> {
  String _firestorePhoto = ''; // real profile photo URL or ''
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    // Seed immediately from the photoUrl already stored on the message so
    // the correct avatar shows before the async Firestore fetch completes.
    final directPhoto = widget.photoUrl;
    if (directPhoto != null && directPhoto.startsWith('http')) {
      _firestorePhoto = directPhoto;
    }
    _resolveProfile();
  }

  @override
  void didUpdateWidget(_SenderAvatar old) {
    super.didUpdateWidget(old);
    if (old.senderId != widget.senderId) _resolveProfile();
    // Also update immediately if the passed-in photoUrl changed.
    if (old.photoUrl != widget.photoUrl) {
      final directPhoto = widget.photoUrl;
      if (directPhoto != null && directPhoto.startsWith('http')) {
        _firestorePhoto = directPhoto;
      }
    }
  }

  Future<void> _resolveProfile() async {
    final id = widget.senderId;
    if (id == null || id.isEmpty) return;

    // Only use cache if we have a confirmed non-empty photo.  Caching an
    // empty string locks out users who later upload a profile photo.
    final ptCached = _senderParentTypeCache.containsKey(id);
    final photoCached = _senderPhotoCache.containsKey(id) &&
        _senderPhotoCache[id]!.isNotEmpty;
    if (ptCached && photoCached) {
      if (mounted) {
        setState(() {
          _firestorePhoto = _senderPhotoCache[id]!;
        });
      }
      return;
    }

    if (_fetching) return;
    _fetching = true;

    try {
      final doc = await FirestoreService().getUserProfile(id);
      final pt = (doc?['parentType'] as String? ?? '').toLowerCase();
      final photo = (doc?['photoUrl'] as String? ?? '').trim();
      _senderParentTypeCache[id] = pt;
      _senderPhotoCache[id] = photo;
      if (mounted) {
        setState(() {
          _firestorePhoto = photo;
        });
      }
    } catch (_) {
      _senderParentTypeCache[id] = '';
      _senderPhotoCache[id] = '';
    } finally {
      _fetching = false;
    }
  }

  /// Plain coloured-circle fallback showing only the sender's first initial.
  /// No illustration asset — keeps avatars clean when no photo is available.
  Widget _buildFallback() {
    final color = _colorFromHex(widget.colorHex);
    final initial = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
    return Container(
      width: 32,
      height: 32,
      color: color.withValues(alpha: 0.20),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(widget.colorHex);

    // Priority 1: photoUrl passed on the message (stored when sent)
    // Priority 2: real photoUrl fetched live from Firestore profile
    // Priority 3: plain coloured-circle with first initial (no illustration)
    final resolvedPhoto = (widget.photoUrl != null && widget.photoUrl!.startsWith('http'))
        ? widget.photoUrl!
        : (_firestorePhoto.startsWith('http') ? _firestorePhoto : null);

    return Stack(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: widget.showTapHint
                ? Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: resolvedPhoto != null
              ? Image.network(
                  resolvedPhoto,
                  fit: BoxFit.cover,
                  width: 32,
                  height: 32,
                  // If the network photo fails, fall back to illustration
                  errorBuilder: (_, __, ___) => _buildFallback(),
                )
              : _buildFallback(),
        ),
        // Tap-hint chat-bubble badge
        if (widget.showTapHint)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: context.hc.surface, width: 1.5),
              ),
              child: const Icon(Icons.chat_bubble, size: 6, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _TimestampDivider extends StatelessWidget {
  final DateTime timestamp;
  const _TimestampDivider({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: context.hc.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(timestamp),
              style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary),
            ),
          ),
          Expanded(child: Divider(color: context.hc.divider)),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP IMAGE MESSAGE — lightweight model for locally-added images
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupImageMessage {
  final String imageUrl;
  final bool isMe;
  final DateTime timestamp;
  final String senderName;
  final String senderAvatar;
  final String senderId;
  final Uint8List? bytes;
  final bool isLocationPin;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;

  const _GroupImageMessage({
    required this.imageUrl,
    required this.isMe,
    required this.timestamp,
    required this.senderName,
    required this.senderAvatar,
    required this.senderId,
    this.bytes,
    this.isLocationPin = false,
    this.latitude,
    this.longitude,
    this.locationLabel,
  });
}

class _GroupDocumentMessage {
  final String fileName;
  final int? fileSize;
  final String fileUrl;   // Firebase Storage download URL (empty for legacy local-only docs)
  final bool isMe;
  final DateTime timestamp;
  final String senderName;
  final String senderAvatar;
  final String senderId;

  const _GroupDocumentMessage({
    required this.fileName,
    this.fileSize,
    this.fileUrl = '',
    required this.isMe,
    required this.timestamp,
    required this.senderName,
    required this.senderAvatar,
    required this.senderId,
  });
}

enum _GChatItemType { text, image, document }

class _GChatItem {
  final _GChatItemType type;
  final int? textIndex;
  final int? imageIndex;
  final int? docIndex;
  final DateTime timestamp;

  const _GChatItem({
    required this.type,
    this.textIndex,
    this.imageIndex,
    this.docIndex,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP IMAGE BUBBLE — shows an image in group chat with forward overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupImageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMe;
  final DateTime timestamp;
  final String senderName;
  final String senderAvatar;
  final String? senderId;
  final VoidCallback? onForward;
  final Uint8List? bytes;

  const _GroupImageBubble({
    required this.imageUrl,
    required this.isMe,
    required this.timestamp,
    required this.senderName,
    required this.senderAvatar,
    this.senderId,
    this.onForward,
    this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 12,
        bottom: 4,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _SenderAvatar(
              colorHex: senderAvatar,
              name: senderName,
              senderId: senderId,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _colorFromHex(senderAvatar),
                      ),
                    ),
                  ),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      child: Container(
                        constraints:
                            const BoxConstraints(maxWidth: 240, maxHeight: 280),
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: bytes != null
                            ? Image.memory(
                                bytes!,
                                fit: BoxFit.cover,
                                width: 240,
                                height: 240,
                                errorBuilder: (_, __, ___) => _brokenImage(),
                              )
                            : (imageUrl.startsWith('http://') ||
                                    imageUrl.startsWith('https://'))
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _brokenImage(),
                                  )
                                : _brokenImage(),
                      ),
                    ),
                    // Forward button overlay
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: onForward,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.forward,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    // Timestamp overlay
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _fmtTime(timestamp),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.white,
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
    );
  }

  Widget _brokenImage() => Container(
        width: 200,
        height: 200,
        color: HuddlColors.background,
        child: Icon(Icons.broken_image, color: HuddlColors.textTertiary, size: 48),
      );

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP LOCATION BUBBLE — shared location in group chat
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupLocationBubble extends StatelessWidget {
  final bool isMe;
  final DateTime timestamp;
  final String senderName;
  final String senderAvatar;
  final String? senderId;
  final String? locationName;
  final double? latitude;
  final double? longitude;

  const _GroupLocationBubble({
    required this.isMe,
    required this.timestamp,
    required this.senderName,
    required this.senderAvatar,
    this.senderId,
    this.locationName,
    this.latitude,
    this.longitude,
  });

  Future<void> _openInMaps(BuildContext context) async {
    final lat = latitude ?? 52.2053;
    final lng = longitude ?? 0.1218;
    final label = locationName ?? 'My Location';
    final googleUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      final geoUrl = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
      try {
        await launchUrl(geoUrl);
      } catch (_) {
        try {
          await launchUrl(googleUrl, mode: LaunchMode.platformDefault);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Could not open maps'),
                backgroundColor: HuddlColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    }
  }

  /// Builds a Google Maps Static API thumbnail URL (no API key needed for basic tiles)
  String _mapThumbnailUrl() {
    final lat = latitude ?? 52.2053;
    final lng = longitude ?? 0.1218;
    // Use OpenStreetMap static tile via staticmap.openstreetmap.de (free, no key)
    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$lat,$lng&zoom=15&size=300x120&markers=$lat,$lng,red-pushpin';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 12, bottom: 4,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _SenderAvatar(colorHex: senderAvatar, name: senderName, senderId: senderId),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _colorFromHex(senderAvatar),
                      ),
                    ),
                  ),
                Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  decoration: BoxDecoration(
                    color: isMe ? HuddlColors.peachLight : HuddlColors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTap: () => _openInMaps(context),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Real map thumbnail ──────────────────────────────
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: Stack(
                          children: [
                            Image.network(
                              _mapThumbnailUrl(),
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 130,
                                  color: const Color(0xFFE8F4EA),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: HuddlColors.primary,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Container(
                                height: 130,
                                color: const Color(0xFFE8F4EA),
                                child: const Icon(Icons.map_outlined, size: 40, color: HuddlColors.primary),
                              ),
                            ),
                            // Red pin overlay centred on the map
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.location_on,
                                  size: 36,
                                  color: HuddlColors.error,
                                  shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 16, color: context.hc.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                locationName ?? 'My location',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: context.hc.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _fmtTime(timestamp),
                              style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      // Open in Maps link
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new, size: 13, color: HuddlColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Open in Google Maps',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GROUP ATTACH SHEET — WhatsApp-style with extra Poll option
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupAttachSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _gAttachIcon(context, Icons.camera_alt_rounded, 'Camera',
                      HuddlColors.primaryDark, HuddlColors.peachLight, 'camera'),
                  _gAttachIcon(context, Icons.photo_library_rounded, 'Gallery',
                      HuddlColors.blue, HuddlColors.blueBackground, 'gallery'),
                  _gAttachIcon(context, Icons.insert_drive_file_rounded, 'Document',
                      HuddlColors.lightBlue, HuddlColors.blueBackground, 'document'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _gAttachIcon(context, Icons.location_on_rounded, 'Location',
                      HuddlColors.accentAmber, HuddlColors.yellowBackground, 'location'),
                  _gAttachIcon(context, Icons.person_rounded, 'Contact',
                      HuddlColors.primary, HuddlColors.peachLight, 'contact'),
                  _gAttachIcon(context, Icons.poll_rounded, 'Poll',
                      HuddlColors.paleBlue, HuddlColors.blueBackground, 'poll'),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _gAttachIcon(BuildContext context, IconData icon, String label,
      Color color, Color bgColor, String action) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, action),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.hc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Utility ───────────────────────────────────────────────────────────────
Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}

// ── Group member model for admin features ─────────────────────────────────
class _GroupMember {
  final String id;
  final String name;
  final Color accentColor;
  final bool isAdmin;

  const _GroupMember({
    required this.id,
    required this.name,
    required this.accentColor,
    this.isAdmin = false,
  });
}
