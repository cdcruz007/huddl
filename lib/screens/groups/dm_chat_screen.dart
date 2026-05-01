import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../models/direct_message.dart';

import '../../services/dm_service.dart';
import '../../services/realtime_dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/user_privacy_prefs_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/saved_message_service.dart';
import '../../services/media_attach_service.dart';
import '../../services/block_service.dart';
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

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kMyBubble = HuddlColors.peachLight;

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
    _conversationId = widget.conversationId;
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
  }

  @override
  void dispose() {
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
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      _conversationId = convId;
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
        setState(() => _messages = converted);
        _scrollToBottom(animate: _messages.isNotEmpty);
      });

      setState(() => _isLoading = false);
    } else {
      // ── DEMO MODE: use local DMService ────────────────────────────────
      await _dmService.initialize();

      final expectedConvId = 'dm_${widget.recipientId}';
      final existing = await _dmService.findConversation(widget.recipientId);
      final resolvedId = existing?.id ?? widget.conversationId ?? expectedConvId;
      _conversationId = resolvedId;

      if (existing != null) {
        await _dmService.markConversationRead(existing.id);
      }

      _messages = await _dmService.getMessages(resolvedId);
      if (_messages.isEmpty && resolvedId != expectedConvId) {
        final fallbackMsgs = await _dmService.getMessages(expectedConvId);
        if (fallbackMsgs.isNotEmpty) {
          _messages = fallbackMsgs;
          _conversationId = expectedConvId;
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
    );
  }

  Future<void> _refreshMessages() async {
    // Use the direct expected conversation ID based on recipientId
    final expectedConvId = 'dm_${widget.recipientId}';
    
    // If no conversation ID set, try to find or derive it
    if (_conversationId == null) {
      final conv = await _dmService.findConversation(widget.recipientId);
      _conversationId = conv?.id ?? expectedConvId;
    }

    // Always check the expected storage key (most reliable)
    final msgs = await _dmService.getMessages(_conversationId!);
    
    // Also try the expected key if different
    List<DirectMessage> allMsgs = msgs;
    if (msgs.isEmpty && _conversationId != expectedConvId) {
      allMsgs = await _dmService.getMessages(expectedConvId);
      if (allMsgs.isNotEmpty) _conversationId = expectedConvId;
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    HapticFeedback.lightImpact();

    if (_isRealUser) {
      // ── Real user: send via Firestore ──────────────────────────────────
      if (_conversationId == null) {
        final convId = await _realtimeDMService.getOrCreateConversation(
          widget.recipientId,
        );
        if (convId == null || convId == 'blocked') return;
        _conversationId = convId;
        // Subscribe to messages now that we have an ID
        _firestoreMsgSub?.cancel();
        _firestoreMsgSub = _realtimeDMService
            .messagesStream(_conversationId!)
            .listen((msgs) {
          if (!mounted) return;
          setState(() => _messages = msgs.map(_realtimeToDirectMessage).toList());
          _scrollToBottom(animate: true);
        });
      }
      await _realtimeDMService.sendMessage(
        conversationId: _conversationId!,
        message: text,
      );
      // Message will appear via the stream subscription — no setState needed
    } else {
      // ── Demo mode: local DMService ─────────────────────────────────────
      if (_conversationId == null) {
        final conv = await _dmService.getOrCreateConversation(
          recipientId: widget.recipientId,
          recipientName: widget.recipientName,
          avatarColor: widget.recipientAvatarColor,
        );
        _conversationId = conv.id;
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
  }

  /// Resend a failed message (P1: tap-to-resend on error)
  Future<void> _resendMessage(DirectMessage failedMsg) async {
    HapticFeedback.lightImpact();
    if (_conversationId == null) return;

    // Remove the old failed message
    setState(() {
      _messages.removeWhere((m) => m.id == failedMsg.id);
    });

    // Re-send with the same text
    if (_isRealUser) {
      if (_conversationId != null) {
        await _realtimeDMService.sendMessage(
          conversationId: _conversationId!,
          message: failedMsg.message,
        );
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
              Icon(Icons.check_circle, color: Colors.white, size: 18),
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

          // ── TEMP DEBUG BANNER ─────────────────────────────────────
          FutureBuilder<String>(
            future: _dumpStorage(),
            builder: (ctx, snap) => GestureDetector(
              onTap: () => setState(() {}), // tap to refresh
              child: Container(
                color: Colors.amber.shade100,
                padding: const EdgeInsets.all(6),
                child: Text(
                  snap.data ?? 'Loading storage...',
                  style: const TextStyle(fontSize: 9, color: Colors.black87, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),

          // ── Messages list ─────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: HuddlColors.primary))
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
                                  onAvatarTap: msg.isMe ? null : () => _showMemberProfileSheet(context),
                                ),
                            ],
                          );
                        },
                      ),
          ),

          // ── Input bar ─────────────────────────────────────────────
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
        icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
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
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isRecipientTyping ? 'typing...' : (_dmService.isUserOnline(widget.recipientId) ? 'Online' : 'Offline'),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: _isRecipientTyping
                        ? HuddlColors.blue
                        : _dmService.isUserOnline(widget.recipientId) ? HuddlColors.teal : HuddlColors.textHint,
                    fontWeight: _isRecipientTyping
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: context.hc.textPrimary),
          onPressed: () => setState(() => _isSearching = true),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.hc.textPrimary),
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
                  Icon(_isBlocked ? Icons.check_circle_outline : Icons.block,
                      size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(_isBlocked ? 'Unblock user' : 'Block user',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'user_details',
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('User details',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'saved',
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('Saved messages',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'search',
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text('Search messages',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'mute',
              child: Row(
                children: [
                  Icon(_conversationId != null && _dmService.isMuted(_conversationId!) ? Icons.notifications_active : Icons.notifications_off_outlined, size: 20, color: context.hc.textPrimary),
                  const SizedBox(width: 12),
                  Text(_conversationId != null && _dmService.isMuted(_conversationId!) ? 'Unmute notifications' : 'Mute notifications',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 20, color: HuddlColors.error),
                  const SizedBox(width: 12),
                  Text('Delete conversation',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.error)),
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
          hintStyle:
              GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
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

  // ── Member profile bottom sheet ────────────────────────────────
  void _showMemberProfileSheet(BuildContext context) {
    final photoUrl = getProfilePhotoForMember(widget.recipientId);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              // Large profile photo
              CircleAvatar(
                radius: 52,
                backgroundColor: _colorFromHex(widget.recipientAvatarColor).withValues(alpha: 0.15),
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Text(
                        widget.recipientName.isNotEmpty ? widget.recipientName[0].toUpperCase() : '?',
                        style: GoogleFonts.poppins(
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: _colorFromHex(widget.recipientAvatarColor),
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                widget.recipientName,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: HuddlColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Online',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: context.hc.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Info cards
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.hc.scaffold,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _profileInfoRow(Icons.person_outline, 'Parent type', 'Mum'),
                    Divider(height: 20, color: context.hc.divider),
                    _profileInfoRow(Icons.location_on_outlined, 'Area', 'Cambridge'),
                    Divider(height: 20, color: context.hc.divider),
                    _profileInfoRow(Icons.child_care_outlined, 'Stage', 'Toddler (1-3 years)'),
                    Divider(height: 20, color: context.hc.divider),
                    _profileInfoRow(Icons.calendar_today_outlined, 'Member since', 'January 2024'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        _focusNode.requestFocus();
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text('Message', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HuddlColors.primary,
                        side: const BorderSide(color: HuddlColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        _showBlockUserDialog();
                      },
                      icon: const Icon(Icons.block, size: 18),
                      label: Text(_isBlocked ? 'Unblock' : 'Block', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.error.withValues(alpha: 0.1),
                        foregroundColor: HuddlColors.error,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
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
        Icon(icon, size: 20, color: HuddlColors.primary),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary)),
        const Spacer(),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: context.hc.textPrimary)),
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
            const Icon(Icons.block, size: 20, color: HuddlColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have blocked ${widget.recipientName}. Unblock to send messages.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: context.hc.textSecondary,
                ),
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
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                ),
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
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: HuddlColors.primary,
                ),
                onPressed: _openAttachSheet,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textTertiary),
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
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _sendMessage();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: HuddlColors.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, size: 18, color: HuddlColors.white),
                      ),
                    );
                  }
                  // Mic button – hold to record
                  return GestureDetector(
                    onLongPressStart: (_) async {
                      // Dismiss keyboard FIRST so iOS doesn't swallow the gesture
                      FocusScope.of(context).unfocus();
                      await Future.delayed(const Duration(milliseconds: 80));
                      if (!mounted) return;
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
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        gradient: HuddlColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, size: 20, color: HuddlColors.white),
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
      // Upload to Firebase Storage
      final convId = _conversationId;
      final audioUrl = await _voiceSvc.uploadVoiceNote(
        result.path,
        conversationId: convId,
      );

      // Send via realtime service if real user
      if (_isRealUser && convId != null) {
        await _realtimeDMService.sendMessage(
          conversationId: convId,
          message: '🎤 Voice message',
          type: 'voice_note',
          audioUrl: audioUrl,
          audioDuration: result.duration,
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
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello and start a conversation!',
            style:
                GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Dump raw storage for this conversation — debug only
  Future<String> _dumpStorage() async {
    try {
      final convId = _conversationId ?? 'dm_${widget.recipientId}';
      final msgs = await _dmService.getMessages(convId);
      if (msgs.isEmpty) return 'convId=$convId\nNO MSGS LOADED (${msgs.length})';
      final snap = msgs.map((m) =>
        'id=${m.id.substring(m.id.length > 10 ? m.id.length - 6 : 0)} '
        'grp=${m.groupData != null ? 'YES(${m.groupData!.keys.length}k)' : 'NO'} '
        'meet=${m.meetupData != null ? 'YES' : 'NO'} '
        'item=${m.itemData != null ? 'YES' : 'NO'}'
      ).join('\n');
      return 'convId=$convId  msgs=${msgs.length}\n$snap';
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  void _confirmDeleteConversation() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete conversation?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This will delete all messages in this conversation.',
          style: GoogleFonts.poppins(color: context.hc.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: context.hc.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              if (_conversationId != null) {
                await _dmService.deleteConversation(_conversationId!);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text('Delete', style: GoogleFonts.poppins(color: HuddlColors.error)),
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
                child: const Icon(Icons.block, size: 32, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text(
                _isBlocked ? 'Unblock ${widget.recipientName}?' : 'Block ${widget.recipientName}?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _isBlocked
                    ? 'They will be able to send you messages and see your profile again.'
                    : 'They will no longer be able to send you messages or see your profile.',
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final wasBlocked = _isBlocked;
                        await _blockService.toggleBlock(widget.recipientId);
                        setState(() {});
                        if (context.mounted) {
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
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.error,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        _isBlocked ? 'Unblock' : 'Block',
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
            ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    const Icon(Icons.bookmark, color: HuddlColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Saved Messages',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${saved.length}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: context.hc.textTertiary,
                      ),
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
                            color: HuddlColors.peachLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bookmark_outline, size: 36, color: HuddlColors.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No saved messages',
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
                            'You have no saved messages currently. Long press on any message to save it.',
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
                    itemCount: saved.length,
                    separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: context.hc.divider),
                    itemBuilder: (_, i) {
                      final msg = saved[i];
                      return ListTile(
                        leading: const Icon(Icons.bookmark, color: HuddlColors.primary, size: 20),
                        title: Text(
                          msg.message,
                          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${msg.senderName} - ${_formatSavedDate(msg.timestamp)}',
                          style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: context.hc.textTertiary),
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

  Future<void> _handleCameraCapture() async {
    final attachment = await _mediaService.takePhoto();
    if (attachment == null || !mounted) return;
    await _sendRichMessage(type: MessageType.image, imageUrl: attachment.filePath ?? 'camera_photo_${DateTime.now().millisecondsSinceEpoch}');
  }

  Future<void> _handleGalleryPick() async {
    final attachments = await _mediaService.pickMultipleImages();
    if (attachments.isEmpty || !mounted) return;
    for (final att in attachments) {
      await _sendRichMessage(type: MessageType.image, imageUrl: att.filePath ?? 'gallery_photo_${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  Future<void> _handleDocumentPick() async {
    final attachment = await _mediaService.pickDocument();
    if (attachment == null || !mounted) return;
    await _sendRichMessage(
      type: MessageType.document,
      documentName: attachment.fileName ?? 'Unknown file',
      documentSize: attachment.fileSize,
    );
  }

  Future<void> _handleLocationShare() async {
    if (!mounted) return;

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
        backgroundColor: const Color(0xFFFF975C),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    double lat = 52.2053;
    double lng = 0.1218;
    String label = 'My location';

    if (kIsWeb) {
      try {
        // Web geolocation placeholder – native GPS via geolocator
        // package can be added in a future sprint for iOS/Android.
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        // Keep Cambridge fallback
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    await _sendRichMessage(
      type: MessageType.location,
      latitude: lat,
      longitude: lng,
      locationLabel: label,
    );
  }

  void _handleContactShare() async {
    if (!mounted) return;
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
        _conversationId = convId;
      }
      await _realtimeDMService.sendMessage(
        conversationId: _conversationId!,
        message: displayMsg,
        type: typeStr,
        imageUrl: imageUrl,
        documentName: documentName,
        documentSize: documentSize,
        latitude: latitude,
        longitude: longitude,
        locationLabel: locationLabel,
        contactName: contactName,
        contactPhone: contactPhone,
      );
      // Stream subscription will update _messages automatically
    } else {
      if (_conversationId == null) {
        final conv = await _dmService.getOrCreateConversation(
          recipientId: widget.recipientId,
          recipientName: widget.recipientName,
          avatarColor: widget.recipientAvatarColor,
        );
        _conversationId = conv.id;
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
            const Icon(Icons.bookmark_added, color: Colors.white, size: 18),
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
  final Map<String, int> reactions;
  final void Function(String emoji)? onTapReaction;

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
                    ),
                  ),
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Container(
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
                        // Time + status ticks
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.timestamp),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: context.hc.textTertiary,
                              ),
                            ),
                            if (isSaved) ...[
                              Icon(Icons.bookmark, size: 12,
                                  color: HuddlColors.primary.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                            ],
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
                                          const Icon(Icons.refresh, size: 12, color: HuddlColors.error),
                                          const SizedBox(width: 2),
                                          Text(
                                            'Retry',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: HuddlColors.error,
                                            ),
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                        style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textSecondary),
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
                        onReact?.call();
                      },
                      child: Container(
                        width: 48,
                        height: 48,
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
                  isSaved ? Icons.bookmark : Icons.bookmark_outline,
                  color: isSaved ? HuddlColors.primary : context.hc.textPrimary,
                ),
                title: Text(
                  isSaved ? 'Unsave message' : 'Save message',
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
          // Received bubbles: bold text with subtle yellow background
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
                _formatTime(timestamp),
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
          child: Icon(Icons.access_time, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.sent:
        return Semantics(
          label: 'Sent',
          child: Icon(Icons.check, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.delivered:
        return Semantics(
          label: 'Delivered',
          child: Icon(Icons.done_all, size: 14, color: context.hc.textTertiary),
        );
      case MessageStatus.read:
        return Semantics(
          label: 'Read',
          child: const Icon(Icons.done_all, size: 14, color: HuddlColors.blue),
        );
      case MessageStatus.error:
        return Semantics(
          label: 'Failed to send, tap to retry',
          child: const Icon(Icons.error_outline, size: 14, color: HuddlColors.error),
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

// ── Illustration avatar asset paths (dad = John.png, mum = Emma.png) ──────
const String _kMumAvatarAsset = 'assets/images/avatars/Emma.png';
const String _kDadAvatarAsset = 'assets/images/avatars/John.png';

/// Per-session cache: memberId → 'mum' | 'dad' | '' (unknown).
final Map<String, String> _dmParentTypeCache = {};

class _RecipientAvatar extends StatefulWidget {
  final String name;
  final String colorHex;
  final String? memberId;
  final double size;

  const _RecipientAvatar({
    required this.name,
    required this.colorHex,
    this.memberId,
    this.size = 32,
  });

  @override
  State<_RecipientAvatar> createState() => _RecipientAvatarState();
}

class _RecipientAvatarState extends State<_RecipientAvatar> {
  String _parentType = '';
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _resolveParentType();
  }

  @override
  void didUpdateWidget(_RecipientAvatar old) {
    super.didUpdateWidget(old);
    if (old.memberId != widget.memberId) _resolveParentType();
  }

  Future<void> _resolveParentType() async {
    final id = widget.memberId;
    if (id == null || id.isEmpty) return;

    if (_dmParentTypeCache.containsKey(id)) {
      if (mounted) setState(() => _parentType = _dmParentTypeCache[id]!);
      return;
    }

    if (_fetching) return;
    _fetching = true;

    try {
      final doc = await FirestoreService().getUserProfile(id);
      final pt = (doc?['parent_type'] as String? ?? '').toLowerCase();
      _dmParentTypeCache[id] = pt;
      if (mounted) setState(() => _parentType = pt);
    } catch (_) {
      _dmParentTypeCache[id] = '';
    } finally {
      _fetching = false;
    }
  }

  String get _fallbackAsset =>
      (_parentType == 'dad') ? _kDadAvatarAsset : _kMumAvatarAsset;

  Widget _buildFallback() => Image.asset(
        _fallbackAsset,
        fit: BoxFit.cover,
        width: widget.size,
        height: widget.size,
      );

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(widget.colorHex);
    // Priority: legacy hardcoded map (demo IDs) → illustration fallback
    final resolvedPhoto = widget.memberId != null
        ? getProfilePhotoForMember(widget.memberId!)
        : null;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: resolvedPhoto != null
          ? Image.network(
              resolvedPhoto,
              fit: BoxFit.cover,
              width: widget.size,
              height: widget.size,
              errorBuilder: (_, __, ___) => _buildFallback(),
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
              style: GoogleFonts.poppins(
                  fontSize: 11, color: context.hc.textTertiary),
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
                    child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _brokenImage(),
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
                      child: const Icon(Icons.forward,
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
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white,
                      ),
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
        color: HuddlColors.background,
        child: Icon(Icons.broken_image, color: HuddlColors.textTertiary, size: 48),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Real map thumbnail ──────────────────────────────
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Stack(
                        children: [
                          Image.network(
                            () {
                              final lat = latitude ?? 52.2053;
                              final lng = longitude ?? 0.1218;
                              return 'https://staticmap.openstreetmap.de/staticmap.php'
                                  '?center=$lat,$lng&zoom=15&size=300x120&markers=$lat,$lng,red-pushpin';
                            }(),
                            height: 130,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: 130,
                                color: const Color(0xFFE8F4EA),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFF975C),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              height: 130,
                              color: const Color(0xFFE8F4EA),
                              child: const Icon(Icons.map_outlined, size: 40, color: Color(0xFFFF975C)),
                            ),
                          ),
                          // Red pin overlay
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.location_on,
                                size: 36,
                                color: Colors.red[700],
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
                              locationLabel ?? 'My location',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(timestamp),
                            style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    // Open in Google Maps link
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
                        color: HuddlColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: HuddlColors.primary, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contactName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: context.hc.textPrimary)),
                          Text(contactPhone, style: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
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
                          child: Icon(Icons.forward, size: 14, color: context.hc.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.phone, size: 13, color: HuddlColors.primary),
                    const SizedBox(width: 4),
                    Text('Call', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
                    const Spacer(),
                    Text(
                      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.poppins(fontSize: 10, color: context.hc.textTertiary),
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
