import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_icons.dart';
import 'dart:io' show File;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/huddl_colors.dart';
import '../../models/direct_message.dart';
import '../main_shell.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';

import '../../services/dm_service.dart';
import '../../services/realtime_dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/user_privacy_prefs_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/saved_message_service.dart';
import '../../services/media_attach_service.dart';
import '../../services/block_service.dart';
import '../../services/report_service.dart';
import '../../services/message_safety_service.dart';
import '../../widgets/chat_safety_notice.dart';
import 'forward_message_sheet.dart';
import '../../widgets/attach_bottom_sheet.dart';
import '../../widgets/document_bubble.dart';
import '../../widgets/emoji_reaction_picker.dart';
import '../../widgets/meetup_invite_card.dart';
import '../../widgets/group_invite_card.dart';
import '../../widgets/item_invite_card.dart';
import '../../widgets/event_invite_card.dart';
import '../../widgets/voice_message_bubble.dart';
import '../../services/voice_message_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/upload_limits.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../../widgets/upgrade_prompt.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
// My-bubble: solid brand orange (Figma spec #E8724A)
const Color _kMyBubble    = HuddlColors.primary;
// Received-bubble: warm parchment #F0EDE8 light / #2E2A26 dark
const Color _kTheirBubbleLight = HuddlColors.receivedBubbleLight;
const Color _kTheirBubbleDark  = HuddlColors.receivedBubbleDark;


/// Maps borough member IDs to realistic profile photo URLs
const Map<String, String> _kMemberProfilePhotos = {
  'mem_emma': 'https://images.pexels.com/photos/733872/pexels-photo-733872.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_sophie': 'https://images.pexels.com/photos/1036623/pexels-photo-1036623.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_james': 'https://images.pexels.com/photos/1222271/pexels-photo-1222271.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_olivia': 'https://images.pexels.com/photos/415829/pexels-photo-415829.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_luke': 'https://images.pexels.com/photos/1043471/pexels-photo-1043471.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_anna': 'https://images.pexels.com/photos/774909/pexels-photo-774909.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_kate': 'https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_david': 'https://images.pexels.com/photos/614810/pexels-photo-614810.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_lucy': 'https://images.pexels.com/photos/1065084/pexels-photo-1065084.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_mark': 'https://images.pexels.com/photos/2379004/pexels-photo-2379004.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_sarah': 'https://images.pexels.com/photos/712513/pexels-photo-712513.jpeg?auto=compress&cs=tinysrgb&w=200',
  'mem_tom': 'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&w=200',
  // Chat demo members (used in group_chat_screen)
  'user_emma': 'https://images.pexels.com/photos/733872/pexels-photo-733872.jpeg?auto=compress&cs=tinysrgb&w=200',
  'user_sophie': 'https://images.pexels.com/photos/1036623/pexels-photo-1036623.jpeg?auto=compress&cs=tinysrgb&w=200',
  'user_kate': 'https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg?auto=compress&cs=tinysrgb&w=200',
  'user_lucy': 'https://images.pexels.com/photos/1065084/pexels-photo-1065084.jpeg?auto=compress&cs=tinysrgb&w=200',
  'user_james': 'https://images.pexels.com/photos/1222271/pexels-photo-1222271.jpeg?auto=compress&cs=tinysrgb&w=200',
  'user_anna': 'https://images.pexels.com/photos/774909/pexels-photo-774909.jpeg?auto=compress&cs=tinysrgb&w=200',
};

/// Get profile photo URL for a member by their ID
String? getProfilePhotoForMember(String memberId) {
  return _kMemberProfilePhotos[memberId];
}

class DMChatScreen extends StatefulWidget {
  final String recipientId;
  final String recipientName;
  final String recipientAvatarColor;
  final String? conversationId; // null = new convo

  const DMChatScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.conversationId,
  });

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final DMService _dmService = DMService();
  final RealtimeDMService _realtimeDMService = RealtimeDMService();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final SavedMessageService _savedMessageService = SavedMessageService();
  final BlockService _blockService = BlockService();
  final VoiceMessageService _voiceSvc = VoiceMessageService.instance;
  bool _isVoiceRecording = false;
  bool _sendPulse = false;
  bool _isSending = false; // SEND-NO-GUARD-1: in-flight send guard

  List<DirectMessage> _messages = [];
  bool _isLoading = true;
  String? _conversationId;
  String _userName = 'You';
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchMatches = []; // indices of matching messages
  int _currentMatchIndex = -1;
  Timer? _refreshTimer;
  final MediaAttachService _mediaService = MediaAttachService();

  // Firestore real-time subscription (for real users)
  StreamSubscription<List<RealtimeDMMessage>>? _firestoreMsgSub;

  /// Returns true if the recipient is a real Firebase user (not a demo member).
  bool get _isRealUser =>
      !widget.recipientId.startsWith('mem_') &&
      widget.recipientId.isNotEmpty &&
      FirebaseAuth.instance.currentUser != null;

  /// IDs of messages unsent "just for me" (hidden locally)
  final Set<String> _hiddenMessageIds = {};

  /// IDs of messages unsent "for everyone" (shown as "This message was deleted")
  final Set<String> _deletedForEveryoneIds = {};


  /// Emoji reactions are now persisted in DirectMessage.reactions via DMService

  @override
  void initState() {
    super.initState();
    _setConversationId(widget.conversationId);
    _loadData();
    if (!_isRealUser) {
      // Demo mode: use local DMService with polling
      _dmService.addListener(_onServiceUpdate);
      _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _refreshMessages();
      });
    }
    _savedMessageService.initialize();
    _blockService.initialize();
    // Tell the shell this DM is now active so foreground FCM banners
    // for this conversation are suppressed (OS heads-up is sufficient).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MainShell.shellKey.currentState?.setActiveDmChat(widget.recipientId);
      // Show AI moderation transparency notice on first ever chat open
      if (mounted) showChatSafetyNoticeIfNeeded(context);
    });
  }

  /// Routes every _conversationId assignment through one place so the shell's
  /// FCM suppression guard (_activeDmConversationId) is updated the moment the
  /// id is known, regardless of which code path resolved it.
  void _setConversationId(String? id) {
    _conversationId = id;
    MainShell.shellKey.currentState?.setActiveDmConversation(id);
  }

  @override
  void dispose() {
    // Clear active chat so banners resume for other conversations.
    MainShell.shellKey.currentState?.setActiveDmChat(null);
    MainShell.shellKey.currentState?.setActiveDmConversation(null);
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _refreshTimer?.cancel();
    _firestoreMsgSub?.cancel();
    if (_isVoiceRecording) _voiceSvc.cancelRecording();
    _dmService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      _refreshMessages();
    }
  }

  Future<void> _loadData() async {
    await _onboardingService.initialize();
    _userName = _onboardingService.name ?? 'You';

    if (_isRealUser) {
      // ── REAL USER MODE: use Firestore ──────────────────────────────────
      // Get or create the conversation document in Firestore
      final convId = await _realtimeDMService.getOrCreateConversation(
        widget.recipientId,
      );

      if (!mounted) return;

      if (convId == null || convId == 'blocked') {
        setState(() => _isLoading = false);
        if (mounted && convId == 'blocked') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You can only message parents in your area.'),
              backgroundColor: HuddlColors.error,
            ),
          );
        }
        return;
      }

      _setConversationId(convId);
      debugPrint('[DM-LISTEN] conversationId: $convId');
      await _realtimeDMService.markConversationRead(convId);

      // Subscribe to real-time message stream
      _firestoreMsgSub = _realtimeDMService
          .messagesStream(convId)
          .listen((firestoreMsgs) {
        if (!mounted) return;
        // Convert RealtimeDMMessage → DirectMessage for the existing UI
        final converted = firestoreMsgs
            .map((m) => _realtimeToDirectMessage(m))
            .toList();
        // De-dup: remove optimistic copies whose clientTempId is now confirmed
        setState(() => _messages = _reconcileOptimistic(converted));
        _scrollToBottom(animate: _messages.isNotEmpty);
      });

      setState(() => _isLoading = false);
    } else {
      // ── DEMO MODE: use local DMService ────────────────────────────────
      await _dmService.initialize();

      final expectedConvId = 'dm_${widget.recipientId}';
      final existing = await _dmService.findConversation(widget.recipientId);
      final resolvedId = existing?.id ?? widget.conversationId ?? expectedConvId;
      _setConversationId(resolvedId);

      if (existing != null) {
        await _dmService.markConversationRead(existing.id);
      }

      _messages = await _dmService.getMessages(resolvedId);
      if (_messages.isEmpty && resolvedId != expectedConvId) {
        final fallbackMsgs = await _dmService.getMessages(expectedConvId);
        if (fallbackMsgs.isNotEmpty) {
          _messages = fallbackMsgs;
          _setConversationId(expectedConvId);
        }
      }

      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  /// Convert a Firestore RealtimeDMMessage to the existing DirectMessage model
  /// so the rich UI (reactions, reply quoting, rich cards) works unchanged.
  DirectMessage _realtimeToDirectMessage(RealtimeDMMessage m) {
    MessageType msgType;
    switch (m.type) {
      case 'image':
        msgType = MessageType.image;
        break;
      case 'document':
        msgType = MessageType.document;
        break;
      case 'location':
        msgType = MessageType.location;
        break;
      case 'contact':
        msgType = MessageType.contact;
        break;
      case 'meetupInvite':
        msgType = MessageType.meetupInvite;
        break;
      case 'voice_note':
        msgType = MessageType.voiceNote;
        break;
      default:
        msgType = MessageType.text;
    }

    MessageStatus msgStatus;
    switch (m.status) {
      case 'delivered':
        msgStatus = MessageStatus.delivered;
        break;
      case 'read':
        msgStatus = MessageStatus.read;
        break;
      case 'failed':
      case 'error':
        msgStatus = MessageStatus.error;
        break;
      default:
        msgStatus = MessageStatus.sent;
    }

    // Convert Firestore reaction format (emoji:uid keys) to simple emoji counts
    final Map<String, int> reactionCounts = {};
    for (final key in m.reactions.keys) {
      final emoji = key.contains(':') ? key.split(':').first : key;
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
    }

    return DirectMessage(
      id: m.id,
      senderId: m.senderId,
      senderName: m.senderName,
      message: m.message,
      timestamp: m.timestamp,
      isMe: m.isMe,
      status: msgStatus,
      reactions: reactionCounts,
      replyToText: m.replyToText,
      replyToSender: m.replyToSender,
      type: msgType,
      imageUrl: m.imageUrl,
      audioUrl: m.audioUrl,
      audioDuration: m.audioDuration,
      documentName: m.documentName,
      documentSize: m.documentSize,
      latitude: m.latitude,
      longitude: m.longitude,
      locationLabel: m.locationLabel,
      contactName: m.contactName,
      contactPhone: m.contactPhone,
      meetupData: m.meetupData,
      groupData: m.groupData,
      itemData: m.itemData,
      eventData: m.eventData,
      senderAvatar: m.senderAvatar,
      clientTempId: m.clientTempId,
    );
  }

  /// De-dup optimistic messages: given a freshly-converted list from Firestore,
  /// remove any local 'msg_'-prefixed optimistic entry whose clientTempId
  /// matches a clientTempId present in [incoming].
  ///
  /// Called on every stream update so reconciliation is race-proof — it runs
  /// independently of the CF callable return, handling both fast-write and
  /// slow-network scenarios.
  List<DirectMessage> _reconcileOptimistic(List<DirectMessage> incoming) {
    // Collect the set of clientTempIds confirmed by the server.
    final confirmedIds = <String>{};
    for (final m in incoming) {
      if (m.clientTempId != null) confirmedIds.add(m.clientTempId!);
    }
    if (confirmedIds.isEmpty) return incoming;

    // Remove local optimistic copies that the server has now acknowledged.
    final retained = _messages
        .where((m) =>
            !(m.id.startsWith('msg_') &&
              m.clientTempId != null &&
              confirmedIds.contains(m.clientTempId)))
        .toList();

    // Merge: keep the retained optimistics (still in-flight) + all server msgs.
    // The incoming list from Firestore is the authoritative ordered list; we
    // prepend any still-pending optimistics so they remain visible at the tail.
    final pendingOptimistics = retained
        .where((m) => m.id.startsWith('msg_'))
        .toList();
    final serverMsgs = incoming;

    // Remove duplicates: server msgs already contain confirmed ones.
    // Result: all server messages + any remaining un-confirmed optimistics.
    return [...serverMsgs, ...pendingOptimistics];
  }

  Future<void> _refreshMessages() async {
    // Use the direct expected conversation ID based on recipientId
    final expectedConvId = 'dm_${widget.recipientId}';
    
    // If no conversation ID set, try to find or derive it
    if (_conversationId == null) {
      final conv = await _dmService.findConversation(widget.recipientId);
      _setConversationId(conv?.id ?? expectedConvId);
    }

    // Always check the expected storage key (most reliable)
    final msgs = await _dmService.getMessages(_conversationId!);
    
    // Also try the expected key if different
    List<DirectMessage> allMsgs = msgs;
    if (msgs.isEmpty && _conversationId != expectedConvId) {
      allMsgs = await _dmService.getMessages(expectedConvId);
      if (allMsgs.isNotEmpty) _setConversationId(expectedConvId);
    }
    
    if (mounted && allMsgs.length != _messages.length) {
      setState(() => _messages = allMsgs);
      _scrollToBottom(animate: true);
    } else if (mounted) {
      // Check status changes
      bool changed = false;
      for (int i = 0; i < allMsgs.length && i < _messages.length; i++) {
        if (allMsgs[i].status != _messages[i].status) {
          changed = true;
          break;
        }
      }
      if (changed) setState(() => _messages = allMsgs);
    }
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animate) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  // ── Voice consent dialog ──────────────────────────────────────────────────
  /// Shows a one-time consent dialog explaining voice message recording policy.
  /// Returns true if the user tapped Allow, false if they cancelled.
  Future<bool> _showVoiceConsentDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Voice Messages',
              style: HuddlText.heading(),
            ),
            content: Text(
              'Huddl records voice messages and uploads them securely to '
              'Firebase Storage. Recordings are deleted from your device '
              'immediately after upload. The recipient can play your voice '
              'messages.\n\n'
              'By tapping Allow, you agree to the Huddl voice message policy.',
              style: HuddlText.body().copyWith(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary),
                child: const Text('Allow',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendMessage() async {
    // ── Subscription gate: message limit ────────────────────────────────────
    if (!SubscriptionService().canSendMessage) {
      if (mounted) {
        showUpgradePrompt(
          context,
          feature: 'messaging',
          message: SubscriptionService().limitReachedMessage('messages'),
          requiredTier: SubscriptionTier.plus,
        );
      }
      return;
    }
    // ── End subscription gate ────────────────────────────────────────────────
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    // SEND-NO-GUARD-1: block double-tap / re-tap during in-flight send.
    // Guard set BEFORE the first await so the async gap is closed.
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
    // ── Safety pre-filter: Layer 1 (local blocklist) + Layer 2 (AI) ────────
    final safetyResult = await MessageSafetyService().classify(text);
    if (safetyResult != MessageSafetyResult.safe) {
      if (mounted) {
        final isLocalBlock = safetyResult == MessageSafetyResult.localBlock;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isLocalBlock
                  ? 'That message contains language that isn\'t allowed in Huddl. '
                    'Please keep our community respectful.'
                  : 'Your message could not be sent — it may violate our community guidelines.',
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

    _messageController.clear();
    HapticFeedback.lightImpact();
    setState(() => _sendPulse = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _sendPulse = false);
    });

    if (_isRealUser) {
      // ── Real user: send via moderateAndSendDM CF ───────────────────────
      if (_conversationId == null) {
        final convId = await _realtimeDMService.getOrCreateConversation(
          widget.recipientId,
        );
        if (convId == null || convId == 'blocked') return;
        _setConversationId(convId);
        // Subscribe to messages now that we have an ID
        _firestoreMsgSub?.cancel();
        _firestoreMsgSub = _realtimeDMService
            .messagesStream(_conversationId!)
            .listen((msgs) {
          if (!mounted) return;
          final converted = msgs.map(_realtimeToDirectMessage).toList();
          // De-dup: remove optimistic copies whose clientTempId is now confirmed
          setState(() => _messages = _reconcileOptimistic(converted));
          _scrollToBottom(animate: true);
        });
      }
      final clientTempId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

      // ── Optimistic insert ──────────────────────────────────────────────
      final optimisticMsg = DirectMessage(
        id: clientTempId,
        senderId: FirebaseAuth.instance.currentUser?.uid ?? '',
        senderName: _userName,
        message: text,
        timestamp: DateTime.now(),
        isMe: true,
        status: MessageStatus.sending,
        clientTempId: clientTempId,
      );
      setState(() => _messages.add(optimisticMsg));
      _scrollToBottom(animate: true);

      final dmResult = await _realtimeDMService.sendMessageModerated(
        conversationId: _conversationId!,
        message: text,
        clientTempId: clientTempId,
      );
      debugPrint('[DM-SEND] conversationId: $_conversationId result: $dmResult');
      if (dmResult == SendDmResult.blocked) {
        setState(() => _messages.removeWhere((m) => m.id == clientTempId));
        if (mounted) {
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
      if (dmResult == SendDmResult.error) {
        // Mark optimistic message as failed so tap-to-resend works
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == clientTempId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(status: MessageStatus.error);
          }
        });
        return;
      }
      // Record message send against subscription limit
      await SubscriptionService().recordMessageSent();
      // Message will appear via the stream subscription — de-dup removes optimistic copy
    } else {
      // ── Demo mode: local DMService ─────────────────────────────────────
      if (_conversationId == null) {
        final conv = await _dmService.getOrCreateConversation(
          recipientId: widget.recipientId,
          recipientName: widget.recipientName,
          avatarColor: widget.recipientAvatarColor,
        );
        _setConversationId(conv.id);
      }
      final msg = await _dmService.sendMessage(
        conversationId: _conversationId!,
        message: text,
        senderName: _userName,
      );
      setState(() {
        _messages.add(msg);
      });
      _scrollToBottom(animate: true);
    }
    } finally {
      // SEND-NO-GUARD-1: always reset — covers normal exit, safety-block, error
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Resend a failed message (P1: tap-to-resend on error)
  Future<void> _resendMessage(DirectMessage failedMsg) async {
    HapticFeedback.lightImpact();
    if (_conversationId == null) return;

    // Remove the old failed message
    setState(() {
      _messages.removeWhere((m) => m.id == failedMsg.id);
    });

    // Re-send with the same text — route through moderated gate so block
    // enforcement and content moderation apply on retry (MODERATION-COVERAGE-1).
    if (_isRealUser) {
      if (_conversationId != null) {
        final r = await _realtimeDMService.sendMessageModerated(
          conversationId: _conversationId!,
          message: failedMsg.message,
        );
        if (r == SendDmResult.blocked && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Your message could not be sent — it may violate our community guidelines.',
            ),
          ));
          // do NOT re-add the message; it was blocked
          return;
        }
      }
    } else {
      final msg = await _dmService.sendMessage(
        conversationId: _conversationId!,
        message: failedMsg.message,
        senderName: _userName,
      );
      setState(() {
        _messages.add(msg);
      });
    }
    _scrollToBottom(animate: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Message resent'),
            ],
          ),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Search logic ────────────────────────────────────────────────────────
  void _performSearch(String query) {
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
      _currentMatchIndex =
          (_currentMatchIndex + 1) % _searchMatches.length;
    });
    _scrollToMessage(_searchMatches[_currentMatchIndex]);
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchMatches.length) %
              _searchMatches.length;
    });
    _scrollToMessage(_searchMatches[_currentMatchIndex]);
  }

  void _scrollToMessage(int index) {
    // Approximate: each message ~80px
    final offset = index * 80.0;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Whether the current recipient is blocked
  bool get _isBlocked => _blockService.isUserBlocked(widget.recipientId);

  // ── Get typing state ────────────────────────────────────────────────────
  bool get _isRecipientTyping {
    if (_conversationId == null) return false;
    final conv = _dmService.conversations.firstWhere(
      (c) => c.id == _conversationId,
      orElse: () => DMConversation(
        id: '',
        recipientId: '',
        recipientName: '',
        recipientAvatarColor: '',
      ),
    );
    return conv.isTyping;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? HuddlColors.darkBackground
          : HuddlColors.warmWhite,   // warm white — matches group chat
      appBar: _isSearching ? _buildSearchAppBar() : _buildAppBar(context),
      body: Column(
        children: [
          // Search results indicator
          if (_isSearching && _searchQuery.isNotEmpty)
            Container(
              color: HuddlColors.neutral50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    _searchMatches.isEmpty
                        ? 'No results'
                        : '${_currentMatchIndex + 1} of ${_searchMatches.length}',
                    style: HuddlText.caption(),
                  ),
                  const Spacer(),
                  if (_searchMatches.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Previous match',
                      icon: const Icon(HuddlIcons.caretUp, size: 20),
                      onPressed: _prevMatch,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      icon: const Icon(HuddlIcons.caretDown, size: 20),
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
                    child:
                        CircularProgressIndicator(color: HuddlColors.textTertiary))
                : (_messages.isEmpty)
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length + (_isRecipientTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Typing indicator as last item
                          if (index == _messages.length && _isRecipientTyping) {
                            return _TypingIndicator(
                                name: widget.recipientName,
                                color: widget.recipientAvatarColor,
                                memberId: widget.recipientId);
                          }
                          if (index >= _messages.length) return const SizedBox.shrink();

                          final msg = _messages[index];

                          // Skip messages unsent "just for me"
                          if (_hiddenMessageIds.contains(msg.id)) {
                            return const SizedBox.shrink();
                          }

                          final showTimestamp = index == 0 ||
                              msg.timestamp
                                      .difference(_messages[index - 1].timestamp)
                                      .inMinutes >
                                  5;

                          // Check if unsent for everyone
                          final isDeletedForEveryone = _deletedForEveryoneIds.contains(msg.id);

                          // Location message
                          if (msg.type == MessageType.location) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                _LocationBubble(
                                  isMe: msg.isMe,
                                  timestamp: msg.timestamp,
                                  recipientName: widget.recipientName,
                                  recipientAvatarColor: widget.recipientAvatarColor,
                                  recipientId: widget.recipientId,
                                  latitude: msg.latitude,
                                  longitude: msg.longitude,
                                  locationLabel: msg.locationLabel,
                                  onForward: () {
                                    showForwardSheet(
                                      context: context,
                                      messageText: '\u{1F4CD} ${msg.locationLabel ?? 'Location'}',
                                      latitude: msg.latitude,
                                      longitude: msg.longitude,
                                      locationLabel: msg.locationLabel,
                                    );
                                  },
                                ),
                              ],
                            );
                          }

                          // Image message
                          if (msg.type == MessageType.image) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                _ImageBubble(
                                  imageUrl: msg.imageUrl ?? '',
                                  isMe: msg.isMe,
                                  timestamp: msg.timestamp,
                                  recipientName: widget.recipientName,
                                  recipientAvatarColor: widget.recipientAvatarColor,
                                  recipientId: widget.recipientId,
                                  onForward: () {
                                    showForwardSheet(context: context, messageText: 'Photo', imageUrl: msg.imageUrl);
                                  },
                                ),
                              ],
                            );
                          }

                          // Document message
                          if (msg.type == MessageType.document) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: 4, bottom: 4,
                                    left: msg.isMe ? 60 : 48, right: msg.isMe ? 0 : 60,
                                  ),
                                  child: Align(
                                    alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                                    child: DocumentBubble(
                                      fileName: msg.documentName ?? 'Document',
                                      fileSize: msg.documentSize,
                                      isMe: msg.isMe,
                                      timestamp: msg.timestamp,
                                      onForward: () {
                                        showForwardSheet(
                                          context: context,
                                          messageText: msg.documentName ?? 'Document',
                                          documentName: msg.documentName,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          // Card checks MUST come before contact/text to ensure cards render
                          // Meetup invite card
                          if (msg.meetupData != null) {
                            if (kDebugMode) {
                              debugPrint('✅ DM: Rendering meetup card for msg ${msg.id}');
                            }
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                MeetupInviteCard(
                                  meetupData: msg.meetupData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Group invite card
                          if (msg.groupData != null) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                GroupInviteCard(
                                  groupData: msg.groupData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Item invite card
                          if (msg.itemData != null) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                ItemInviteCard(
                                  itemData: msg.itemData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Event invite card
                          if (msg.eventData != null) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                EventInviteCard(
                                  eventData: msg.eventData!,
                                  isMe: msg.isMe,
                                ),
                              ],
                            );
                          }

                          // Voice note message
                          if (msg.type == MessageType.voiceNote && msg.audioUrl != null) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: 4, bottom: 4,
                                    left: msg.isMe ? 60 : 8,
                                    right: msg.isMe ? 8 : 60,
                                  ),
                                  child: Align(
                                    alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
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

                          // Contact message
                          if (msg.type == MessageType.contact) {
                            return Column(
                              children: [
                                if (showTimestamp) _TimestampDivider(timestamp: msg.timestamp),
                                _ContactBubble(
                                  isMe: msg.isMe,
                                  contactName: msg.contactName ?? 'Unknown',
                                  contactPhone: msg.contactPhone ?? '',
                                  timestamp: msg.timestamp,
                                  onForward: () {
                                    showForwardSheet(
                                      context: context,
                                      messageText: '\u{1F464} ${msg.contactName}',
                                      contactName: msg.contactName,
                                      contactPhone: msg.contactPhone,
                                    );
                                  },
                                ),
                              ],
                            );
                          }

                          final isHighlighted = _isSearching &&
                              _searchMatches.isNotEmpty &&
                              _currentMatchIndex >= 0 &&
                              _currentMatchIndex < _searchMatches.length &&
                              _searchMatches[_currentMatchIndex] == index;

                          return Column(
                            children: [
                              if (showTimestamp)
                                _TimestampDivider(timestamp: msg.timestamp),
                              if (isDeletedForEveryone)
                                _DeletedMessageBubble(
                                  isMe: msg.isMe,
                                  timestamp: msg.timestamp,
                                )
                              else
                                _DMBubble(
                                  message: msg,
                                  recipientName: widget.recipientName,
                                  recipientAvatarColor:
                                      widget.recipientAvatarColor,
                                  recipientId: widget.recipientId,
                                  isHighlighted: isHighlighted,
                                  searchQuery: _searchQuery,
                                  isSaved: _savedMessageService.isMessageSaved(msg.id),
                                  // Pass the snapshotted sender avatar so the
                                  // bubble renders immediately without a per-
                                  // message Firestore profile lookup.
                                  senderAvatarUrl: msg.isMe ? null : msg.senderAvatar,
                                  onSave: () => _saveMessage(msg),
                                  onForward: () {
                                    showForwardSheet(
                                      context: context,
                                      messageText: msg.message,
                                    );
                                  },
                                  onReact: () => _showEmojiPicker(msg.id),
                                  reactions: msg.reactions,
                                  onTapReaction: (emoji) => _toggleReaction(msg.id, emoji),
                                  onCopy: () => _copyMessage(msg.message),
                                  onUnsend: msg.isMe ? () => _showUnsendDialog(msg) : null,
                                  onResend: msg.isMe && msg.status == MessageStatus.error
                                      ? () => _resendMessage(msg)
                                      : null,
                                  onReportUser: !msg.isMe
                                      ? () => _showReportMessageDialog(msg.id, widget.recipientId, msg.message)
                                      : null,
                                  onAvatarTap: msg.isMe ? null : () => _showMemberProfileSheet(context),
                                ),
                            ],
                          );
                        },
                      ),
          ),

          // ── Safety notice strip + Input bar ───────────────────────
          const ChatSafetyStrip(),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: context.hc.surface,
      leading: IconButton(
        tooltip: 'Back',
        icon: Icon(HuddlIcons.arrowBack, color: Theme.of(context).colorScheme.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          _RecipientAvatar(
            name: widget.recipientName,
            colorHex: widget.recipientAvatarColor,
            memberId: widget.recipientId,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipientName,
                  style: HuddlText.body(weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isRecipientTyping ? 'typing...' : (_dmService.isUserOnline(widget.recipientId) ? 'Online' : 'Offline'),
                  style: HuddlText.caption(color: _dmService.isUserOnline(widget.recipientId) ? HuddlColors.success : HuddlColors.textHint),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Search messages',
          icon: Icon(HuddlIcons.search, color: context.hc.textPrimary),
          onPressed: () => setState(() => _isSearching = true),
        ),
        PopupMenuButton<String>(
          tooltip: 'More options',
          icon: Icon(HuddlIcons.moreVert, color: context.hc.textPrimary),
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: context.hc.surface,
          elevation: 8,
          onSelected: (value) async {
            switch (value) {
              case 'block':
                _showBlockUserDialog();
                break;
              case 'user_details':
                _showMemberProfileSheet(context);
                break;
              case 'saved':
                _showSavedMessagesForDM();
                break;
              case 'search':
                setState(() => _isSearching = true);
                break;
              case 'mute':
                if (_conversationId != null) {
                  await _dmService.toggleMute(_conversationId!);
                  final muted = _dmService.isMuted(_conversationId!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(muted ? 'Notifications muted' : 'Notifications unmuted')),
                    );
                    setState(() {});
                  }
                }
                break;
              case 'delete':
                _confirmDeleteConversation();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'block',
              child: Row(
                children: [
                  Icon(_isBlocked ? HuddlIcons.checkCircle : HuddlIcons.block,
                      size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(_isBlocked ? 'Unblock user' : 'Block user',
                      style: HuddlText.body()),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'user_details',
              child: Row(
                children: [
                  Icon(HuddlIcons.user, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('User details',
                      style: HuddlText.body()),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'saved',
              child: Row(
                children: [
                  Icon(HuddlIcons.bookmark, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('Saved messages',
                      style: HuddlText.body()),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'search',
              child: Row(
                children: [
                  Icon(HuddlIcons.search, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('Search messages',
                      style: HuddlText.body()),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'mute',
              child: Row(
                children: [
                  Icon(_conversationId != null && _dmService.isMuted(_conversationId!) ? HuddlIcons.bellRingingFill : HuddlIcons.bellSlash, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(_conversationId != null && _dmService.isMuted(_conversationId!) ? 'Unmute notifications' : 'Mute notifications',
                      style: HuddlText.body()),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(HuddlIcons.delete, size: 20, color: HuddlColors.error),
                  const SizedBox(width: 12),
                  Text('Delete conversation',
                      style: HuddlText.body(color: HuddlColors.error)),
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

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: context.hc.surface,
      leading: IconButton(
        tooltip: 'Exit search',
        icon: Icon(HuddlIcons.arrowBack, color: Theme.of(context).colorScheme.onSurface),
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
        style: HuddlText.body(color: context.hc.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search messages...',
          hintStyle:
              HuddlText.body(color: context.hc.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        onChanged: _performSearch,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: context.hc.divider),
      ),
    );
  }

  // ── Copy message ──────────────────────────────────────────────────
  void _copyMessage(String text) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
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

  // ── Member profile bottom sheet ────────────────────────────────
  Future<void> _showMemberProfileSheet(BuildContext context) async {
    // Load real profile data from users_public/{recipientId} before opening
    // the sheet — these fields are set during onboarding and mirrored by
    // syncPublicProfile. Falls back gracefully if any field is absent.
    Map<String, dynamic>? publicProfile;
    try {
      publicProfile = await FirestoreService().getUserProfile(widget.recipientId);
    } catch (_) {}

    if (!context.mounted) return;

    // photoUrl from users_public (mirrored by syncPublicProfile on upload).
    // Falls back to initials avatar if the user hasn't set a profile photo.
    final photoUrl = (publicProfile?['photoUrl'] as String? ?? '').trim();
    final hasPhoto = photoUrl.isNotEmpty && photoUrl.startsWith('http');

    // ── Resolve display values from real onboarding fields ────────────────
    final parentType = (publicProfile?['parentType'] as String? ?? '').trim();
    final area       = (publicProfile?['borough']    as String? ?? '').trim();
    final rawStages  = publicProfile?['stagesOfLife'];
    final stages     = rawStages is List
        ? rawStages.cast<String>()
        : <String>[];

    // Map stagesOfLife values to onboarding-accurate labels (no age inference).
    // These keys are set on the onboarding journey — never derived from DOB.
    String stageLabel = '';
    if (stages.isNotEmpty) {
      final parts = stages.map((s) {
        switch (s) {
          case 'aspiring':  return 'Hoping to conceive';
          case 'expecting': return 'Expecting';
          case 'parent':    return 'Parent';
          default:          return s;
        }
      }).where((s) => s.isNotEmpty).toList();
      stageLabel = parts.join(' · ');
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              // Large profile photo — real Firestore photoUrl or initials fallback
              CircleAvatar(
                radius: 52,
                backgroundColor: _colorFromHex(widget.recipientAvatarColor).withValues(alpha: 0.15),
                backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                child: hasPhoto
                    ? null
                    : Text(
                        widget.recipientName.isNotEmpty ? widget.recipientName[0].toUpperCase() : '?',
                        style: HuddlText.display(color: _colorFromHex(widget.recipientAvatarColor)),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.recipientName,
                style: HuddlText.display(),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: HuddlColors.nearBlack,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Online',
                    style: HuddlText.body(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Info rows — only shown when the field has a real value
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.hc.scaffold,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    if (parentType.isNotEmpty) ...[  
                      _profileInfoRow(HuddlIcons.user, 'Parent type', parentType),
                    ],
                    if (parentType.isNotEmpty && area.isNotEmpty)
                      Divider(height: 20, color: context.hc.divider),
                    if (area.isNotEmpty) ...[  
                      _profileInfoRow(HuddlIcons.locationPin, 'Area', area),
                    ],
                    if (area.isNotEmpty && stageLabel.isNotEmpty)
                      Divider(height: 20, color: context.hc.divider),
                    if (stageLabel.isNotEmpty) ...[  
                      _profileInfoRow(HuddlIcons.childCare, 'Stage', stageLabel),
                    ],
                    // Member since omitted — createdAt is not in users_public
                    // (private field) and cannot be read for other users.
                    if (parentType.isEmpty && area.isEmpty && stageLabel.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No profile info available',
                          style: HuddlText.body(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: HuddlButton(
                      label: 'Message',
                      variant: HuddlButtonVariant.secondary,
                      leadingIcon: HuddlIcons.chat,
                      fullWidth: true,
                      onPressed: () {
                        Navigator.pop(c);
                        _focusNode.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: HuddlButton(
                      label: _isBlocked ? 'Unblock' : 'Block',
                      variant: HuddlButtonVariant.destructive,
                      leadingIcon: HuddlIcons.block,
                      fullWidth: true,
                      onPressed: () {
                        Navigator.pop(c);
                        _showBlockUserDialog();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── Report User ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    _showReportUserDialog(widget.recipientId, widget.recipientName);
                  },
                  icon: const Icon(HuddlIcons.flag, size: 18, color: HuddlColors.error),
                  label: Text(
                    'Report ${widget.recipientName}',
                    style: HuddlText.body(),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.hc.textPrimary),
        const SizedBox(width: 12),
        Text(label, style: HuddlText.body(color: context.hc.textSecondary)),
        const Spacer(),
        Text(value, style: HuddlText.body(color: context.hc.textPrimary)),
      ],
    );
  }

  Widget _buildInputBar() {
    // Show blocked banner instead of input bar when user is blocked
    if (_isBlocked) {
      return Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: context.hc.surface,
          border: Border(top: BorderSide(color: context.hc.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(HuddlIcons.block, size: 20, color: HuddlColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have blocked ${widget.recipientName}. Unblock to send messages.',
                style: HuddlText.body(),
              ),
            ),
            TextButton(
              onPressed: () async {
                await _blockService.unblockUser(widget.recipientId);
                setState(() {});
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${widget.recipientName} has been unblocked'),
                      backgroundColor: HuddlColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: Text(
                'Unblock',
                style: HuddlText.body(weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // ── Voice recording mode ─────────────────────────────────────────────────
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
        // ── Main input row ─────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
              8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: BoxDecoration(
            color: context.hc.surface,
            border:
                Border(top: BorderSide(color: context.hc.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Attach file',
                icon: const Icon(
                  HuddlIcons.addCircle,
                  color: HuddlColors.primary,  // orange — action button
                  size: 26,
                ),
                onPressed: _openAttachSheet,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? HuddlColors.darkInputBg
                        : HuddlColors.receivedBubbleLight, // warm grey-beige
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
                    style: HuddlText.body(color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message ${widget.recipientName.split(' ').first}…',
                      hintStyle: HuddlText.body(color: context.hc.textTertiary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Mic button (hold to record) when text is empty; send button when text exists
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  if (hasText) {
                    return Semantics(
                      label: 'Send message',
                      button: true,
                      child: GestureDetector(
                        // SEND-NO-GUARD-1: disable tap while send in-flight
                        onTap: _isSending ? null : () {
                          HapticFeedback.lightImpact();
                          _sendMessage();
                        },
                        child: AnimatedScale(
                          scale: _sendPulse ? 1.25 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: HuddlColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(HuddlIcons.send, size: 18, color: HuddlColors.white),
                          ),
                        ),
                      ),
                    );
                  }
                  // Mic button – hold to record
                  return Semantics(
                    label: 'Record voice message',
                    button: true,
                    child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (_) async {
                      // Dismiss keyboard FIRST so iOS doesn't swallow the gesture
                      FocusScope.of(context).unfocus();
                      await Future.delayed(const Duration(milliseconds: 80));
                      if (!mounted) return;

                      // Check voice message consent (required by ToS and Privacy Policy).
                      final prefs = UserPrivacyPrefsService();
                      await prefs.load();
                      if (!prefs.voiceMessageConsent) {
                        final granted = await _showVoiceConsentDialog();
                        if (!granted || !mounted) return;
                        await prefs.setSetting(
                            UserPrivacyPrefsService.keyVoiceConsent, true);
                      }

                      final hasPerms = await _voiceSvc.hasPermission();
                      if (!hasPerms) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Microphone permission required for voice messages.')),
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
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: HuddlColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(HuddlIcons.mic, size: 22, color: HuddlColors.white),
                        ),
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

  // ── Send voice message ──────────────────────────────────────────────────
  Future<void> _sendVoiceMessage() async {
    final result = await _voiceSvc.stopRecording();
    if (mounted) setState(() => _isVoiceRecording = false);
    if (result == null || result.duration < 1) return; // too short – discard

    try {
      // S-04: resolve conversationId BEFORE upload. The Storage rule for
      // voice_notes/dm/{cid}/... requires the conversation doc to exist.
      final convId = await _ensureConversationId();
      if (convId == null || !mounted) return;

      final audioUrl = await _voiceSvc.uploadVoiceNote(
        result.path,
        pathType: VoiceNotePathType.dm,
        contextId: convId,
      );

      // Send via moderated CF if real user
      if (_isRealUser) {
        final voiceTempId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
        await _realtimeDMService.sendMessageModerated(
          conversationId: convId,
          message: '🎤 Voice message',
          type: 'voice_note',
          audioUrl: audioUrl,
          audioDuration: result.duration,
          clientTempId: voiceTempId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    }
  }

  // ── Unsend message ──────────────────────────────────────────────────
  void _showUnsendDialog(DirectMessage msg) {
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
                  color: HuddlColors.neutral50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(HuddlIcons.delete, size: 32, color: HuddlColors.textDark),
              ),
              const SizedBox(height: 18),
              Text(
                'Unsend message?',
                style: HuddlText.heading(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose how you want to unsend this message.',
                style: HuddlText.body(color: context.hc.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Unsend for everyone
              HuddlButton(
                label: 'Unsend for everyone',
                variant: HuddlButtonVariant.destructive,
                leadingIcon: HuddlIcons.usersThree,
                fullWidth: true,
                onPressed: () {
                  Navigator.pop(c);
                  setState(() {
                    _deletedForEveryoneIds.add(msg.id);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
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
              ),
              const SizedBox(height: 10),
              // Unsend just for me
              HuddlButton(
                label: 'Unsend just for me',
                variant: HuddlButtonVariant.secondary,
                leadingIcon: HuddlIcons.user,
                fullWidth: true,
                onPressed: () {
                  Navigator.pop(c);
                  setState(() {
                    _hiddenMessageIds.add(msg.id);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
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
              ),
              const SizedBox(height: 10),
              // Cancel
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text('Cancel',
                    style: HuddlText.body(color: context.hc.textTertiary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RecipientAvatar(
            name: widget.recipientName,
            colorHex: widget.recipientAvatarColor,
            memberId: widget.recipientId,
            size: 72,
          ),
          const SizedBox(height: 16),
          Text(
            widget.recipientName,
            style: HuddlText.heading(),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello and start a conversation!',
            style:
                HuddlText.body(color: context.hc.textTertiary),
          ),
        ],
      ),
    );
  }



  void _confirmDeleteConversation() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete conversation?',
            style: HuddlText.body(weight: FontWeight.w600)),
        content: Text(
          'This will delete all messages in this conversation.',
          style: HuddlText.body(color: context.hc.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel',
                style: HuddlText.body(color: context.hc.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              if (_conversationId != null) {
                await _dmService.deleteConversation(_conversationId!);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text('Delete', style: HuddlText.body(color: HuddlColors.error)),
          ),
        ],
      ),
    );
  }

  // ── Block user dialog (matches screenshot design) ─────────────────
  void _showBlockUserDialog() {
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
                child: const Icon(HuddlIcons.block, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                _isBlocked ? 'Unblock ${widget.recipientName}?' : 'Block ${widget.recipientName}?',
                style: HuddlText.heading(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _isBlocked
                    ? 'They will be able to send you messages and see your profile again.'
                    : 'They will no longer be able to send you messages or see your profile.',
                style: HuddlText.body(color: context.hc.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: HuddlButton(
                      label: 'Cancel',
                      variant: HuddlButtonVariant.secondary,
                      fullWidth: true,
                      onPressed: () => Navigator.pop(c),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: HuddlButton(
                      label: _isBlocked ? 'Unblock' : 'Block',
                      variant: HuddlButtonVariant.destructive,
                      fullWidth: true,
                      onPressed: () async {
                        Navigator.pop(c);
                        final wasBlocked = _isBlocked;
                        // BLOCK-SILENT-1: capture real result; false-after-block
                        // means the write failed and the optimistic state was
                        // rolled back — show error instead of success.
                        final result = await _blockService.toggleBlock(widget.recipientId);
                        setState(() {});
                        if (context.mounted) {
                          // Blocking failed: write rolled back, user is not blocked.
                          if (!wasBlocked && !result) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Could not block ${widget.recipientName}. Check your connection and try again.'),
                                backgroundColor: HuddlColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(wasBlocked
                                    ? '${widget.recipientName} has been unblocked'
                                    : '${widget.recipientName} has been blocked'),
                                backgroundColor: HuddlColors.primary,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            );
                          }
                        }
                      },
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

  // ── Report message dialog ─────────────────────────────────────────
  void _showReportMessageDialog(String messageId, String? targetUserId, String messageText) {
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
                      child: const Icon(HuddlIcons.flag, size: 22, color: HuddlColors.error),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Report message',
                      style: HuddlText.heading(color: context.hc.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Why are you reporting this message from ${widget.recipientName}?',
                  style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.4),
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
                                style: HuddlText.body(color: context.hc.textPrimary)),
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
                      child: HuddlButton(
                        label: 'Cancel',
                        variant: HuddlButtonVariant.secondary,
                        fullWidth: true,
                        onPressed: () => Navigator.pop(c),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HuddlButton(
                        label: 'Report',
                        variant: HuddlButtonVariant.destructive,
                        fullWidth: true,
                        onPressed: selectedType == null
                            ? null
                            : () async {
                                Navigator.pop(c);
                                final ok = await reportService.submitReport(
                                  contentId: messageId,
                                  targetUserId: targetUserId ?? '',
                                  type: selectedType!,
                                  context: ReportContext.dmMessage,
                                  chatName: 'DM with ${widget.recipientName}',
                                  messagePreview: messageText,
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

  // ── Report User dialog (profile-level report) ────────────────────
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
                      child: const Icon(HuddlIcons.flag, size: 22, color: HuddlColors.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Report $targetName',
                        style: HuddlText.heading(color: context.hc.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Why are you reporting this user?',
                  style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.4),
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
                                  style: HuddlText.body(color: context.hc.textPrimary)),
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
                      child: HuddlButton(
                        label: 'Cancel',
                        variant: HuddlButtonVariant.secondary,
                        fullWidth: true,
                        onPressed: () => Navigator.pop(c),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HuddlButton(
                        label: 'Report',
                        variant: HuddlButtonVariant.destructive,
                        fullWidth: true,
                        onPressed: selectedType == null
                            ? null
                            : () async {
                                Navigator.pop(c);
                                final ok = await reportService.submitReport(
                                  contentId: targetUserId,
                                  targetUserId: targetUserId,
                                  type: selectedType!,
                                  context: ReportContext.userProfile,
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

  // ── Saved messages for this DM ───────────────────────────────────
  void _showSavedMessagesForDM() {
    final saved = _savedMessageService.getSavedForDM(widget.recipientId);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
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
                    const Icon(HuddlIcons.bookmark, color: HuddlColors.textDark, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Saved Messages',
                      style: HuddlText.heading(),
                    ),
                    const Spacer(),
                    Text(
                      '${saved.length}',
                      style: HuddlText.body(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: context.hc.divider),
              if (saved.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: HuddlColors.neutral50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(HuddlIcons.bookmark, size: 36, color: HuddlColors.textDark),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No saved messages',
                          style: HuddlText.body(weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            'You have no saved messages currently. Long press on any message to save it.',
                            style: HuddlText.body(color: context.hc.textSecondary),
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
                    itemCount: saved.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: context.hc.divider),
                    itemBuilder: (_, i) {
                      final msg = saved[i];
                      return ListTile(
                        leading: const Icon(HuddlIcons.bookmark, color: HuddlColors.textDark, size: 20),
                        title: Text(
                          msg.message,
                          style: HuddlText.body(color: context.hc.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${msg.senderName} - ${_formatSavedDate(msg.timestamp)}',
                          style: HuddlText.caption(color: context.hc.textTertiary),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove saved message',
                          icon: Icon(HuddlIcons.delete, size: 18, color: context.hc.textTertiary),
                          onPressed: () {
                            _savedMessageService.unsaveMessage(msg.id);
                            Navigator.pop(c);
                            _showSavedMessagesForDM();
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
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

  // ── Media permission prompt ────────────────────────────────────────────
  // ── WhatsApp-style attach handler ────────────────────────────────────
  Future<void> _openAttachSheet() async {
    final action = await showAttachBottomSheet(context);
    if (action == null || !mounted) return;

    switch (action) {
      case AttachAction.camera:
        await _handleCameraCapture();
        break;
      case AttachAction.gallery:
        await _handleGalleryPick();
        break;
      case AttachAction.document:
        await _handleDocumentPick();
        break;
      case AttachAction.location:
        _handleLocationShare();
        break;
      case AttachAction.contact:
        _handleContactShare();
        break;
    }
  }

  // ── Upload helper: bytes or file path → Firebase Storage URL ───────────
  Future<String?> _uploadMediaToStorage({
    required Uint8List? bytes,
    required String? filePath,
    required String mimeType,
    required String folder,
    required String conversationId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final ext = mimeType.contains('/') ? mimeType.split('/').last : 'bin';
    // S-01/S-02: scoped path — conversationId is a path segment so Storage
    // rules can do firestore.get(conversations/{cid}).participants check.
    final ref = FirebaseStorage.instance.ref('$folder/$conversationId/${uid}_$ts.$ext');
    try {
      TaskSnapshot snap;
      if (bytes != null) {
        // LAYER-11-NO-SIZE-PRECHECK-1: reject before hitting Storage rule
        final sizeErr = UploadLimits.checkSize(bytes.length, UploadLimits.mediaMb, kind: 'file');
        if (sizeErr != null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sizeErr)));
          return null;
        }
        snap = await ref.putData(bytes, SettableMetadata(contentType: mimeType));
      } else if (filePath != null && !kIsWeb) {
        snap = await ref.putFile(File(filePath));
      } else {
        return null;
      }
      return await snap.ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[DMChat] Storage upload error: $e');
      }
      return null;
    }
  }

  /// S-01/S-02: Resolve _conversationId BEFORE any media upload.
  /// The new Storage rules do firestore.get(conversations/{cid}).participants —
  /// the conversation doc must exist at upload time for the rule to allow the write.
  /// Returns the resolved conversationId, or null if resolution failed (blocked/error).
  Future<String?> _ensureConversationId() async {
    if (_conversationId != null) return _conversationId;
    if (_isRealUser) {
      final convId = await _realtimeDMService.getOrCreateConversation(
        widget.recipientId,
      );
      if (convId == null || convId == 'blocked') return null;
      _setConversationId(convId);
      // Set up message stream if not already subscribed
      _firestoreMsgSub ??= _realtimeDMService
          .messagesStream(_conversationId!)
          .listen((msgs) {
        if (!mounted) return;
        final converted = msgs.map(_realtimeToDirectMessage).toList();
        // De-dup: remove optimistic copies whose clientTempId is now confirmed
        setState(() => _messages = _reconcileOptimistic(converted));
        _scrollToBottom(animate: true);
      });
    } else {
      final conv = await _dmService.getOrCreateConversation(
        recipientId: widget.recipientId,
        recipientName: widget.recipientName,
        avatarColor: widget.recipientAvatarColor,
      );
      _setConversationId(conv.id);
    }
    return _conversationId;
  }

  Future<void> _handleCameraCapture() async {
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Camera permission required to take photos'),
              backgroundColor: HuddlColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }
    }
    final MediaAttachment? attachment;
    try {
      attachment = await _mediaService.takePhoto();
      if (attachment == null || !mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't open the camera. Please try again."),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    // S-01: resolve conversationId BEFORE upload so the Storage rule's
    // firestore.get(conversations/{cid}).participants can resolve.
    final cid = await _ensureConversationId();
    if (cid == null || !mounted) return;
    final downloadUrl = await _uploadMediaToStorage(
      bytes: attachment.bytes,
      filePath: attachment.filePath,
      mimeType: attachment.mimeType ?? 'image/jpeg',
      folder: 'dm_images',
      conversationId: cid,
    );
    if (!mounted) return;
    if (downloadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload photo. Please try again.')),
      );
      return;
    }
    await _sendRichMessage(type: MessageType.image, imageUrl: downloadUrl);
  }

  Future<void> _handleGalleryPick() async {
    // image_picker uses PHPickerViewController (iOS 14+) and the OS photo
    // picker on Android 13+ — neither requires a runtime permission grant.
    // Permission.photos.request() was a no-op: it logged and fell through
    // regardless of result, so it has been removed.
    final attachments = await _mediaService.pickMultipleImages();
    if (attachments.isEmpty || !mounted) return;
    // S-01: resolve conversationId once before the upload loop.
    final cid = await _ensureConversationId();
    if (cid == null || !mounted) return;
    for (final att in attachments) {
      final downloadUrl = await _uploadMediaToStorage(
        bytes: att.bytes,
        filePath: att.filePath,
        mimeType: att.mimeType ?? 'image/jpeg',
        folder: 'dm_images',
        conversationId: cid,
      );
      if (downloadUrl == null) continue; // skip if upload failed
      if (!mounted) return;
      await _sendRichMessage(type: MessageType.image, imageUrl: downloadUrl);
    }
  }

  Future<void> _handleDocumentPick() async {
    final attachment = await _mediaService.pickDocument();
    if (attachment == null || !mounted) return;
    // S-02: resolve conversationId BEFORE upload.
    final cid = await _ensureConversationId();
    if (cid == null || !mounted) return;
    String? downloadUrl;
    if (attachment.bytes != null || (attachment.filePath != null && !kIsWeb)) {
      downloadUrl = await _uploadMediaToStorage(
        bytes: attachment.bytes,
        filePath: attachment.filePath,
        mimeType: attachment.mimeType ?? 'application/octet-stream',
        folder: 'dm_documents',
        conversationId: cid,
      );
    }
    await _sendRichMessage(
      type: MessageType.document,
      documentUrl: downloadUrl,
      documentName: attachment.fileName ?? 'Unknown file',
      documentSize: attachment.fileSize,
    );
  }

  Future<void> _handleLocationShare() async {
    if (!mounted) return;

    // ── 1. Permission check (native only; web uses browser prompt via geolocator) ──
    if (!kIsWeb) {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              permission == LocationPermission.deniedForever
                  ? 'Location permission permanently denied. Enable it in Settings.'
                  : 'Location permission denied.',
              style: HuddlText.body(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: permission == LocationPermission.deniedForever
                ? SnackBarAction(
                    label: 'Settings',
                    textColor: Colors.white,
                    onPressed: () => openAppSettings(),
                  )
                : null,
          ),
        );
        return;
      }
    }

    // ── 2. Show "getting location…" progress snackbar ──────────────────────
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Getting your location…', style: HuddlText.body()),
          ],
        ),
        backgroundColor: HuddlColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    // ── 3. Obtain real GPS position ─────────────────────────────────────────
    double? lat;
    double? lng;
    String label = 'My location';

    try {
      // Medium accuracy gets a fix faster (network/cell) before GPS warms up.
      // 30s timeout gives GPS enough time even indoors.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 30),
        );
      } catch (_) {
        // Fall back to last known position if fresh GPS fix times out
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) throw Exception('No position available');
      lat = position.latitude;
      lng = position.longitude;
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[DMChat] Geolocation error: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final permission = await Geolocator.checkPermission();
      final isPermissionIssue = permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPermissionIssue
                ? 'Location permission denied. Please allow location access in Settings.'
                : 'Could not get your location. Make sure location is enabled and try again.',
            style: HuddlText.body(),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: isPermissionIssue
              ? SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                )
              : null,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // ── 4. Send location message ────────────────────────────────────────────
    await _sendRichMessage(
      type: MessageType.location,
      latitude: lat,
      longitude: lng,
      locationLabel: label,
    );
  }

  // ── Contacts permission helpers ────────────────────────────────────────
  //
  // WHY a two-step check-then-request?
  // On iOS, once the user has denied the system prompt, the permission enters
  // "permanentlyDenied" state.  Calling Permission.contacts.request() when
  // already permanentlyDenied is a silent no-op — iOS never shows the system
  // alert again.  By checking status first we can detect this state early and
  // immediately route the user to Settings instead of silently returning denied.
  //
  // Flow:
  //   granted           → return true, proceed
  //   notDetermined     → call request() → granted? true : false (snackbar)
  //   denied            → call request() → iOS shows prompt once more
  //                        result granted? true : false (snackbar)
  //   permanentlyDenied → show Settings dialog (openAppSettings), return false
  //   restricted        → show explanatory snackbar, return false
  Future<bool> _requestContactsPermission() async {
    PermissionStatus status = await Permission.contacts.status;

    // Already granted — fast path.
    if (status.isGranted) return true;

    // Permanently denied — request() won't show system prompt on iOS/Android.
    // Route user straight to Settings with a proper dialog.
    if (status.isPermanentlyDenied) {
      if (mounted) _showContactsSettingsDialog();
      return false;
    }

    // Restricted (parental controls / MDM) — cannot request.
    if (status.isRestricted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Contacts access is restricted on this device.',
              style: HuddlText.body(),
            ),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return false;
    }

    // notDetermined or denied — ask the OS to show the system permission prompt.
    final result = await Permission.contacts.request();

    if (result.isGranted) return true;

    if (!mounted) return false;

    // The user tapped "Don't Allow" on the system prompt — now permanently denied.
    if (result.isPermanentlyDenied) {
      _showContactsSettingsDialog();
      return false;
    }

    // Plain denied (user dismissed without granting).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Contacts permission is needed to share a contact card.',
          style: HuddlText.body(),
        ),
        backgroundColor: HuddlColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return false;
  }

  /// Full-screen dialog explaining why contacts are needed and offering a
  /// direct deep-link into the OS Settings app via [openAppSettings()].
  void _showContactsSettingsDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: ctx.hc.surface,
        title: Row(
          children: [
            Icon(HuddlIcons.contacts, color: HuddlColors.primary, size: 24),
            const SizedBox(width: 10),
            Text(
              'Contacts Access',
              style: HuddlText.heading(),
            ),
          ],
        ),
        content: Text(
          'Huddl needs access to your contacts so you can share '
          'contact cards in group and direct message chats.\n\n'
          'Please open Settings and enable Contacts for Huddl.',
          style: HuddlText.body(color: ctx.hc.textSecondary).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: HuddlText.body(),
            ),
          ),
          HuddlButton(
            label: 'Open Settings',
            variant: HuddlButtonVariant.primary,
            fullWidth: false,
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  void _handleContactShare() async {
    if (!mounted) return;

    // ── Contacts permission gate (native only) ────────────────────────────
    // iOS/Android: check status BEFORE calling request().
    //   • notDetermined / denied → call request() so the OS system prompt appears.
    //   • permanentlyDenied      → request() is a no-op on iOS; show Settings dialog.
    //   • granted                → proceed directly.
    if (!kIsWeb) {
      final granted = await _requestContactsPermission();
      if (!granted) return; // dialog already shown; manual entry NOT offered when perm denied
    }

    // ── Manual contact entry bottom sheet ──────────────────────────────────
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: ctx.hc.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: ctx.hc.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Share Contact',
                    style: HuddlText.heading(color: ctx.hc.textPrimary),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Name', style: HuddlText.body(weight: FontWeight.w600, color: ctx.hc.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Contact name',
                    hintStyle: HuddlText.body(color: HuddlColors.textHint),
                    filled: true,
                    fillColor: ctx.hc.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: HuddlText.body(),
                ),
                const SizedBox(height: 14),
                Text('Phone number', style: HuddlText.body(weight: FontWeight.w600, color: ctx.hc.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+44 7700 900000',
                    hintStyle: HuddlText.body(color: HuddlColors.textHint),
                    filled: true,
                    fillColor: ctx.hc.inputBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: HuddlText.body(),
                ),
                const SizedBox(height: 20),
                HuddlButton(
                  label: 'Share',
                  variant: HuddlButtonVariant.primary,
                  fullWidth: true,
                  onPressed: () {
                    final n = nameCtrl.text.trim();
                    if (n.isEmpty) return;
                    Navigator.pop(ctx, {'name': n, 'phone': phoneCtrl.text.trim()});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (result != null && mounted) {
      await _sendRichMessage(
        type: MessageType.contact,
        contactName: result['name'],
        contactPhone: result['phone'],
      );
    }
  }

  /// Helper to send a rich (non-text) message through the appropriate service
  Future<void> _sendRichMessage({
    required MessageType type,
    String? imageUrl,
    String? documentUrl,
    String? documentName,
    int? documentSize,
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? contactName,
    String? contactPhone,
  }) async {
    String displayMsg = '';
    switch (type) {
      case MessageType.image: displayMsg = 'Photo'; break;
      case MessageType.document: displayMsg = documentName ?? 'Document'; break;
      case MessageType.location: displayMsg = locationLabel ?? 'Location'; break;
      case MessageType.contact: displayMsg = contactName ?? 'Contact'; break;
      case MessageType.meetupInvite: displayMsg = 'Meetup invite'; break;
      case MessageType.voiceNote: displayMsg = '🎤 Voice message'; break;
      case MessageType.text: break;
    }

    final typeStr = type.name; // e.g. 'image', 'document', 'location'

    if (_isRealUser) {
      if (_conversationId == null) {
        final convId = await _realtimeDMService.getOrCreateConversation(
          widget.recipientId,
        );
        if (convId == null || convId == 'blocked') return;
        _setConversationId(convId);
      }
      final mediaTempId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      await _realtimeDMService.sendMessageModerated(
        conversationId: _conversationId!,
        message: displayMsg,
        type: typeStr,
        imageUrl: imageUrl ?? documentUrl, // imageUrl doubles as download URL for docs
        documentName: documentName,
        documentSize: documentSize,
        latitude: latitude,
        longitude: longitude,
        locationLabel: locationLabel,
        contactName: contactName,
        contactPhone: contactPhone,
        clientTempId: mediaTempId,
      );
      // Stream subscription will update _messages automatically
    } else {
      if (_conversationId == null) {
        final conv = await _dmService.getOrCreateConversation(
          recipientId: widget.recipientId,
          recipientName: widget.recipientName,
          avatarColor: widget.recipientAvatarColor,
        );
        _setConversationId(conv.id);
      }
      await _dmService.sendMessage(
        conversationId: _conversationId!,
        message: displayMsg,
        senderName: _userName,
        type: type,
        imageUrl: imageUrl,
        documentName: documentName,
        documentSize: documentSize,
        latitude: latitude,
        longitude: longitude,
        locationLabel: locationLabel,
        contactName: contactName,
        contactPhone: contactPhone,
      );
      _messages = await _dmService.getMessages(_conversationId!);
      setState(() {});
    }
    _scrollToBottom(animate: true);
  }

  // ── Emoji reactions ────────────────────────────────────────────────────
  Future<void> _showEmojiPicker(String messageId) async {
    final emoji = await showEmojiReactionPicker(context);
    if (emoji != null && mounted) {
      _toggleReaction(messageId, emoji);
    }
  }

  void _toggleReaction(String messageId, String emoji) async {
    if (_conversationId == null) return;
    if (_isRealUser) {
      await _realtimeDMService.toggleReaction(_conversationId!, messageId, emoji);
      // Stream subscription handles UI update
    } else {
      await _dmService.toggleReaction(_conversationId!, messageId, emoji);
      _messages = await _dmService.getMessages(_conversationId!);
      if (mounted) setState(() {});
    }
  }

  void _saveMessage(DirectMessage msg) {
    if (_savedMessageService.isMessageSaved(msg.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message already saved'),
          backgroundColor: HuddlColors.textHint,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    _savedMessageService.saveDMMessage(
      messageId: msg.id,
      message: msg.message,
      senderName: msg.senderName,
      timestamp: msg.timestamp,
      recipientId: widget.recipientId,
      recipientName: widget.recipientName,
      recipientAvatarColor: widget.recipientAvatarColor,
      conversationId: _conversationId,
    );

    setState(() {}); // refresh saved state

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(HuddlIcons.bookmarkFill, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('Message saved to Saved tab')),
          ],
        ),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DM CHAT BUBBLE — with message status ticks
// ═══════════════════════════════════════════════════════════════════════════════

class _DMBubble extends StatelessWidget {
  final DirectMessage message;
  final String recipientName;
  final String recipientAvatarColor;
  final String? recipientId;
  final bool isHighlighted;
  final String searchQuery;
  final bool isSaved;
  final VoidCallback? onSave;
  final VoidCallback? onForward;
  final VoidCallback? onReact;
  final VoidCallback? onCopy;
  final VoidCallback? onUnsend;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onResend;
  final VoidCallback? onReportUser;
  final Map<String, int> reactions;
  final void Function(String emoji)? onTapReaction;
  /// Pre-resolved sender photo URL — forwarded to _RecipientAvatar so the
  /// avatar renders immediately without a per-bubble Firestore lookup.
  final String? senderAvatarUrl;

  const _DMBubble({
    required this.message,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.recipientId,
    this.isHighlighted = false,
    this.searchQuery = '',
    this.isSaved = false,
    this.onSave,
    this.onForward,
    this.onReact,
    this.onCopy,
    this.onUnsend,
    this.onAvatarTap,
    this.onResend,
    this.onReportUser,
    this.reactions = const {},
    this.onTapReaction,
    this.senderAvatarUrl,
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
              top: 4,
              bottom: reactions.isEmpty ? 4 : 0,
              left: isMe ? 60 : 0,
              right: isMe ? 0 : 60,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe)
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: _RecipientAvatar(
                      name: recipientName,
                      colorHex: recipientAvatarColor,
                      memberId: recipientId,
                      size: 32,
                      photoUrl: senderAvatarUrl,
                    ),
                  ),
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                    Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isHighlighted
                          ? HuddlColors.primary.withValues(alpha: 0.12)
                          : isMe
                              ? _kMyBubble  // orange — sent
                              : Theme.of(context).brightness == Brightness.dark
                                  ? _kTheirBubbleDark   // warm dark brown
                                  : _kTheirBubbleLight, // warm parchment
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Message text (with search highlighting)
                        searchQuery.isNotEmpty
                            ? _buildHighlightedText(context, message.message, searchQuery, isMe: isMe)
                            : Text(
                                message.message,
                                style: HuddlText.body(color: isMe ? HuddlColors.white : context.hc.textPrimary),
                              ),
                      ],
                    ),
                  ),
                      // Timestamp row — outside bubble (Figma spec)
                      Padding(
                        padding: EdgeInsets.only(
                          top: 3,
                          left: isMe ? 0 : 2,
                          right: isMe ? 2 : 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSaved) ...[
                              Icon(HuddlIcons.bookmark, size: 11,
                                  color: HuddlColors.textTertiary),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              _formatTime(message.timestamp),
                              style: HuddlText.caption(),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              if (message.status == MessageStatus.error && onResend != null)
                                Semantics(
                                  label: 'Failed to send, tap to retry',
                                  button: true,
                                  child: GestureDetector(
                                    onTap: onResend,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: HuddlColors.error.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(HuddlIcons.refresh, size: 12, color: HuddlColors.error),
                                          const SizedBox(width: 2),
                                          Text(
                                            'Retry',
                                            style: HuddlText.label(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else
                                _MessageStatusIcon(status: message.status),
                            ],
                          ],
                        ),
                      ),       // end timestamp Padding
                    ],         // end Flexible > Column children
                  ),           // end Flexible > Column
                ),             // end Flexible
              ],               // end outer Row children
            ),                 // end outer Row
          ),                   // end GestureDetector
        ),
        // Emoji reactions row
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
    // Capture all callbacks and state values before entering the builder so
    // the sheet's own context (c) is used for all theme lookups — the stale
    // widget-build context must never be referenced inside the builder.
    final capturedOnTapReaction = onTapReaction;
    final capturedOnReact = onReact;
    final capturedOnSave = onSave;
    final capturedOnCopy = onCopy;
    final capturedOnForward = onForward;
    final capturedOnUnsend = onUnsend;
    final capturedOnReportUser = onReportUser;
    final capturedIsSaved = isSaved;
    final capturedMessage = message;

    showModalBottomSheet(
      context: context,
      // isScrollControlled: true lets the sheet grow beyond 50% screen height
      // — without it, the list tiles are clipped on smaller phones.
      isScrollControlled: true,
      // useRootNavigator: true ensures the sheet is shown above any nested
      // Navigator inside the chat ListView on Android.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) {
        final hc = c.hc;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hc.scaffold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(HuddlIcons.chat, size: 16, color: hc.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          capturedMessage.message,
                          style: HuddlText.caption(color: hc.textSecondary),
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
                          capturedOnTapReaction?.call(emoji);
                        },
                        child: Semantics(
                          label: 'React with $emoji',
                          button: true,
                          child: Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            child: Text(emoji, style: const TextStyle(fontSize: 24)),
                          ),
                        ),
                      )),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(c);
                          capturedOnReact?.call();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hc.scaffold,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(HuddlIcons.add, color: hc.textSecondary, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: hc.divider),
                ListTile(
                  leading: Icon(
                    capturedIsSaved ? HuddlIcons.bookmark : HuddlIcons.bookmark,
                    color: capturedIsSaved ? HuddlColors.error : hc.textPrimary,
                  ),
                  title: Text(
                    capturedIsSaved ? 'Unsave message' : 'Save message',
                    style: HuddlText.body(),
                  ),
                  onTap: () {
                    Navigator.pop(c);
                    capturedOnSave?.call();
                  },
                ),
                ListTile(
                  leading: Icon(HuddlIcons.copy, color: hc.textPrimary),
                  title: Text('Copy text',
                      style: HuddlText.body()),
                  onTap: () {
                    Navigator.pop(c);
                    capturedOnCopy?.call();
                  },
                ),
                ListTile(
                  leading: Icon(HuddlIcons.forward, color: hc.textPrimary),
                  title: Text('Forward',
                      style: HuddlText.body()),
                  onTap: () {
                    Navigator.pop(c);
                    capturedOnForward?.call();
                  },
                ),
                if (capturedOnUnsend != null)
                  ListTile(
                    leading: const Icon(HuddlIcons.delete, color: HuddlColors.error),
                    title: Text('Unsend message',
                        style: HuddlText.body(color: HuddlColors.error)),
                    onTap: () {
                      Navigator.pop(c);
                      capturedOnUnsend.call();
                    },
                  ),
                if (capturedOnReportUser != null)
                  ListTile(
                    leading: const Icon(HuddlIcons.flag, color: HuddlColors.error),
                    title: Text('Report message',
                        style: HuddlText.body(color: HuddlColors.error)),
                    onTap: () {
                      Navigator.pop(c);
                      capturedOnReportUser.call();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(BuildContext context, String text, String query, {bool isMe = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isMe ? HuddlColors.white : (isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark);
    if (query.isEmpty) {
      return Text(text,
          style: HuddlText.body(color: baseColor).copyWith(height: 1.4));
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
          // Received bubbles: bold text with subtle yellow background
          backgroundColor: isMe
              ? HuddlColors.primaryDark   // deeper coral for sent bubbles
              : HuddlColors.primary.withValues(alpha: 0.15), // soft brand tint for received bubbles
          fontWeight: FontWeight.w700,
          color: isMe ? Colors.white : (isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark),
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(
        style: HuddlText.body(color: baseColor).copyWith(height: 1.4),
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

// ═══════════════════════════════════════════════════════════════════════════════
// DELETED MESSAGE BUBBLE — shown when message is unsent for everyone
// ═══════════════════════════════════════════════════════════════════════════════

class _DeletedMessageBubble extends StatelessWidget {
  final bool isMe;
  final DateTime timestamp;

  const _DeletedMessageBubble({
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
              Icon(HuddlIcons.block, size: 14, color: context.hc.textTertiary),
              const SizedBox(width: 6),
              Text(
                'This message was deleted',
                style: HuddlText.body().copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(timestamp),
                style: HuddlText.label(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGE STATUS ICON — sending / sent / delivered / read / error
// ═══════════════════════════════════════════════════════════════════════════════

class _MessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _MessageStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    // If the current user has read receipts disabled, never show the blue
    // "read" tick — cap the display at "delivered" (grey double-tick).
    final effectiveStatus =
        (!UserPrivacyPrefsService().readReceipts &&
                status == MessageStatus.read)
            ? MessageStatus.delivered
            : status;

    switch (effectiveStatus) {
      case MessageStatus.sending:
        return Semantics(
          label: 'Sending',
          child: Icon(HuddlIcons.clock, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.sent:
        return Semantics(
          label: 'Sent',
          child: Icon(HuddlIcons.check, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.delivered:
        return Semantics(
          label: 'Delivered',
          child: Icon(HuddlIcons.check, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.read:
        return Semantics(
          label: 'Read',
          child: const Icon(HuddlIcons.check, size: 14, color: HuddlColors.nearBlack),
        );
      case MessageStatus.error:
        return Semantics(
          label: 'Failed to send, tap to retry',
          child: const Icon(HuddlIcons.error, size: 14, color: HuddlColors.error),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPING INDICATOR — animated dots
// ═══════════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatefulWidget {
  final String name;
  final String color;
  final String? memberId;
  const _TypingIndicator({required this.name, required this.color, this.memberId});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.name} is typing',
      liveRegion: true,
      child: Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RecipientAvatar(
              name: widget.name, colorHex: widget.color, memberId: widget.memberId, size: 32),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.2;
                    final t = (_controller.value - delay).clamp(0.0, 1.0);
                    final scale = 0.5 + 0.5 * (1.0 - (2.0 * t - 1.0).abs());
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: context.hc.textTertiary
                            .withValues(alpha: 0.3 + 0.7 * scale),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECIPIENT AVATAR — circle with initials
// ═══════════════════════════════════════════════════════════════════════════════

/// Per-session cache: memberId → parentType (kept for Firestore read consistency).
final Map<String, String> _dmParentTypeCache = {};

/// Per-session cache: memberId → real Firestore photoUrl ('' = no photo).
final Map<String, String> _dmPhotoCache = {};

class _RecipientAvatar extends StatefulWidget {
  final String name;
  final String colorHex;
  final String? memberId;
  final double size;
  /// Pre-resolved photo URL from the message doc — skips Firestore fetch
  /// when non-empty.  Falls back to live lookup when null or empty.
  final String? photoUrl;

  const _RecipientAvatar({
    required this.name,
    required this.colorHex,
    this.memberId,
    this.size = 32,
    this.photoUrl,
  });

  @override
  State<_RecipientAvatar> createState() => _RecipientAvatarState();
}

class _RecipientAvatarState extends State<_RecipientAvatar> {
  String _firestorePhoto = ''; // real profile photo URL or ''
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _resolveProfile();
  }

  @override
  void didUpdateWidget(_RecipientAvatar old) {
    super.didUpdateWidget(old);
    if (old.memberId != widget.memberId) _resolveProfile();
  }

  Future<void> _resolveProfile() async {
    final id = widget.memberId;
    if (id == null || id.isEmpty) return;

    // If the caller already resolved the photo (e.g. from message.senderAvatar)
    // use it immediately and skip the Firestore lookup entirely.
    final preResolved = widget.photoUrl;
    if (preResolved != null && preResolved.startsWith('http')) {
      if (mounted) setState(() => _firestorePhoto = preResolved);
      // Still fetch parent type for the illustration fallback in case the
      // network image fails, but don't block the avatar on it.
    }

    final ptCached = _dmParentTypeCache.containsKey(id);
    // Only use the photo cache when it holds a real URL.  Caching an empty
    // string prevents re-fetching after the user later uploads a profile photo.
    final photoCached = _dmPhotoCache.containsKey(id) &&
        _dmPhotoCache[id]!.isNotEmpty;
    if (ptCached && photoCached) {
      if (mounted) {
        setState(() {
          // Only override the pre-resolved URL if cache has a newer one
          if (_firestorePhoto.isEmpty) _firestorePhoto = _dmPhotoCache[id]!;
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
      _dmParentTypeCache[id] = pt;
      _dmPhotoCache[id] = photo;
      if (mounted) {
        setState(() {
          _firestorePhoto = photo;
        });
      }
    } catch (_) {
      _dmParentTypeCache[id] = '';
      _dmPhotoCache[id] = '';
    } finally {
      _fetching = false;
    }
  }

  /// Gender-appropriate illustrated avatar fallback.
  /// Uses John.png for dads, Emma.png for mums/others.
  /// Falls back to a grey initial circle if the asset fails to load.
  Widget _buildFallback() {
    final pt = widget.memberId != null
        ? (_dmParentTypeCache[widget.memberId!] ?? '')
        : '';
    final asset = pt == 'dad'
        ? 'assets/images/avatars/John.png'
        : 'assets/images/avatars/Emma.png';
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        color: HuddlColors.peachWarm,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Opacity(
          opacity: 0.82,
          child: Image.asset(
            asset,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              final initial = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
              return Center(
                child: Text(
                  initial,
                  style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.white),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Priority 1: pre-resolved photo from message doc (fastest — no network)
    // Priority 2: live Firestore profile photo
    // Priority 3: gender-appropriate illustrated avatar (John/Emma)
    final preResolved = widget.photoUrl;
    final resolvedPhoto = (preResolved != null && preResolved.startsWith('http'))
        ? preResolved
        : _firestorePhoto.startsWith('http')
            ? _firestorePhoto
            : null;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: HuddlColors.textTertiary.withValues(alpha: 0.20),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: resolvedPhoto != null
          ? CachedNetworkImage(
              imageUrl: resolvedPhoto,
              fit: BoxFit.cover,
              width: widget.size,
              height: widget.size,
              memCacheWidth: 300,
              errorWidget: (_, __, ___) => _buildFallback(),
            )
          : _buildFallback(),
    );
  }
}

// ── TIMESTAMP DIVIDER ──────────────────────────────────────────────────────

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
              style: HuddlText.caption(color: context.hc.textTertiary),
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

// _AttachMenuOption removed — replaced by WhatsApp-style attach_bottom_sheet.dart

// ═══════════════════════════════════════════════════════════════════════════════
// IMAGE BUBBLE — shows an image in the chat with a forward overlay icon
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageBubble extends StatelessWidget {
  final String imageUrl;
  final bool isMe;
  final DateTime timestamp;
  final String recipientName;
  final String recipientAvatarColor;
  final String? recipientId;
  final VoidCallback? onForward;

  const _ImageBubble({
    required this.imageUrl,
    required this.isMe,
    required this.timestamp,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.recipientId,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 4,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            _RecipientAvatar(
              name: recipientName,
              colorHex: recipientAvatarColor,
              memberId: recipientId,
              size: 32,
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Stack(
              children: [
                // Image container
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240, maxHeight: 280),
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            errorWidget: (_, __, ___) => _brokenImage(),
                          ),
                  ),
                ),
                // Forward button overlay — bottom left (matching design)
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
                      child: const Icon(HuddlIcons.forward,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
                // Timestamp overlay — bottom right
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatTime(timestamp),
                      style: HuddlText.label(),
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

  Widget _brokenImage() => Container(
        width: 200,
        height: 200,
        color: HuddlColors.neutral50,
        child: Icon(HuddlIcons.brokenImage, color: HuddlColors.textTertiary, size: 48),
      );

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOCATION BUBBLE — shows a location pin preview (like WhatsApp shared location)
// ═══════════════════════════════════════════════════════════════════════════════

class _LocationBubble extends StatelessWidget {
  final bool isMe;
  final DateTime timestamp;
  final String recipientName;
  final String recipientAvatarColor;
  final String? recipientId;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final VoidCallback? onForward;

  const _LocationBubble({
    required this.isMe,
    required this.timestamp,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.recipientId,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.onForward,
  });

  Future<void> _openInMaps(BuildContext context) async {
    final lat = latitude ?? 52.2053;
    final lng = longitude ?? 0.1218;
    final label = locationLabel ?? 'Shared Location';
    // Use coordinates directly for reliable map opening
    final googleUrl = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Fallback: try geo: URI
      final geoUrl = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
      try {
        await launchUrl(geoUrl);
      } catch (_) {
        // Last resort: open in browser tab
        try {
          await launchUrl(googleUrl, mode: LaunchMode.platformDefault);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Could not open maps'),
                backgroundColor: HuddlColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 8, bottom: 4,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            _RecipientAvatar(
              name: recipientName,
              colorHex: recipientAvatarColor,
              memberId: recipientId,
              size: 32,
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: () => _openInMaps(context),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: isMe
                      ? HuddlColors.primary.withValues(alpha: 0.10)
                      : (Theme.of(context).brightness == Brightness.dark
                          ? HuddlColors.darkSurface
                          : HuddlColors.white),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Real map thumbnail ──────────────────────────────
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Stack(
                        children: [
                          CachedNetworkImage(
                            imageUrl: () {
                              final lat = latitude ?? 52.2053;
                              final lng = longitude ?? 0.1218;
                              return 'https://staticmap.openstreetmap.de/staticmap.php'
                                  '?center=$lat,$lng&zoom=15&size=300x120&markers=$lat,$lng,red-pushpin';
                            }(),
                            height: 130,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                            placeholder: (ctx, __) => Container(
                              height: 130,
                              color: HuddlColors.successBg,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: HuddlColors.primaryDark,
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              height: 130,
                              color: HuddlColors.successBg,
                              child: const Icon(HuddlIcons.map, size: 40, color: HuddlColors.primaryDark),
                            ),
                          ),
                          // Red pin overlay
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: Icon(
                                HuddlIcons.locationPinFill,
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
                          Icon(HuddlIcons.locationPin, size: 16, color: context.hc.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              locationLabel ?? 'My location',
                              style: HuddlText.body(),
                            ),
                          ),
                          Text(
                            _formatTime(timestamp),
                            style: HuddlText.label(color: context.hc.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    // Open in Google Maps link
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Row(
                        children: [
                          Icon(HuddlIcons.openInNew, size: 13, color: HuddlColors.textDark),
                          const SizedBox(width: 4),
                          Text(
                            'Open in Google Maps',
                            style: HuddlText.caption(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONTACT BUBBLE — shows a shared contact card
// ═══════════════════════════════════════════════════════════════════════════════
class _ContactBubble extends StatelessWidget {
  final bool isMe;
  final String contactName;
  final String contactPhone;
  final DateTime timestamp;
  final VoidCallback? onForward;

  const _ContactBubble({
    required this.isMe,
    required this.contactName,
    required this.contactPhone,
    required this.timestamp,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 8, bottom: 4,
        left: isMe ? 60 : 48, right: isMe ? 0 : 60,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: isMe
                ? HuddlColors.primary.withValues(alpha: 0.10)
                : (Theme.of(context).brightness == Brightness.dark
                    ? HuddlColors.darkSurface
                    : HuddlColors.white),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? HuddlColors.darkSurfaceVariant
                            : HuddlColors.neutral50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(HuddlIcons.user, color: context.hc.textPrimary, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contactName, style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                          Text(contactPhone, style: HuddlText.caption(color: context.hc.textTertiary)),
                        ],
                      ),
                    ),
                    if (onForward != null)
                      GestureDetector(
                        onTap: onForward,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(HuddlIcons.forward, size: 14, color: context.hc.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Icon(HuddlIcons.phone, size: 13, color: context.hc.textPrimary),
                    const SizedBox(width: 4),
                    Text('Call', style: HuddlText.caption(color: context.hc.textPrimary)),
                    const Spacer(),
                    Text(
                      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                      style: HuddlText.label(color: context.hc.textTertiary),
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
}

// ── Utility ───────────────────────────────────────────────────────────────
Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
