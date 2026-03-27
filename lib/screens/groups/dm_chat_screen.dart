import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/direct_message.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';
import '../../services/media_attach_service.dart';
import '../../services/block_service.dart';
import 'forward_message_sheet.dart';
import '../../widgets/attach_bottom_sheet.dart';
import '../../widgets/document_bubble.dart';
import '../../widgets/emoji_reaction_picker.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kMyBubble = Color(0xFFFFF3ED);

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
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final SavedMessageService _savedMessageService = SavedMessageService();
  final BlockService _blockService = BlockService();

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

  /// IDs of messages unsent "just for me" (hidden locally)
  final Set<String> _hiddenMessageIds = {};

  /// IDs of messages unsent "for everyone" (shown as "This message was deleted")
  final Set<String> _deletedForEveryoneIds = {};

  /// Reply state
  DirectMessage? _replyingTo;

  /// Locally added image messages
  final List<_ImageChatMessage> _imageMessages = [];

  /// Locally added document messages
  final List<_DocumentChatMessage> _documentMessages = [];

  /// Emoji reactions: messageId → { emoji → count }
  final Map<String, Map<String, int>> _reactions = {};

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _loadData();
    _dmService.addListener(_onServiceUpdate);
    _savedMessageService.initialize();
    _blockService.initialize();
    // Periodic refresh for status changes
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _refreshMessages();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _refreshTimer?.cancel();
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
    await _dmService.initialize();
    _userName = _onboardingService.name ?? 'You';

    // Get or create conversation
    final conv = await _dmService.getOrCreateConversation(
      recipientId: widget.recipientId,
      recipientName: widget.recipientName,
      avatarColor: widget.recipientAvatarColor,
    );
    _conversationId = conv.id;

    // Mark as read
    await _dmService.markConversationRead(conv.id);

    // Load messages
    _messages = await _dmService.getMessages(conv.id);

    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _refreshMessages() async {
    if (_conversationId == null) return;
    final msgs = await _dmService.getMessages(_conversationId!);
    if (mounted && msgs.length != _messages.length) {
      setState(() => _messages = msgs);
      _scrollToBottom(animate: true);
    } else if (mounted) {
      // Check status changes
      bool changed = false;
      for (int i = 0; i < msgs.length && i < _messages.length; i++) {
        if (msgs[i].status != _messages[i].status) {
          changed = true;
          break;
        }
      }
      if (changed) setState(() => _messages = msgs);
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
    if (text.isEmpty || _conversationId == null) return;

    _messageController.clear();

    final msg = await _dmService.sendMessage(
      conversationId: _conversationId!,
      message: text,
      senderName: _userName,
      replyToText: _replyingTo?.message,
      replyToSender: _replyingTo != null ? (_replyingTo!.isMe ? 'You' : widget.recipientName) : null,
    );

    setState(() {
      _messages.add(msg);
      _replyingTo = null;
    });
    _scrollToBottom(animate: true);
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
      backgroundColor: HuddlColors.background,
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
                      color: HuddlColors.textSecondary,
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
                    child:
                        CircularProgressIndicator(color: HuddlColors.primary))
                : (_messages.isEmpty && _imageMessages.isEmpty)
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _sortedItems.length + (_isRecipientTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          final items = _sortedItems;
                          // Typing indicator as last item
                          if (index == items.length && _isRecipientTyping) {
                            return _TypingIndicator(
                                name: widget.recipientName,
                                color: widget.recipientAvatarColor,
                                memberId: widget.recipientId);
                          }
                          if (index >= items.length) return const SizedBox.shrink();
                          final item = items[index];

                          // Image / location message
                          if (item.type == _ChatItemType.image) {
                            final imgMsg = _imageMessages[item.imageIndex!];
                            if (imgMsg.isLocationPin) {
                              return _LocationBubble(
                                isMe: imgMsg.isMe,
                                timestamp: imgMsg.timestamp,
                                recipientName: widget.recipientName,
                                recipientAvatarColor: widget.recipientAvatarColor,
                                recipientId: widget.recipientId,
                              );
                            }
                            return _ImageBubble(
                              imageUrl: imgMsg.imageUrl,
                              isMe: imgMsg.isMe,
                              timestamp: imgMsg.timestamp,
                              recipientName: widget.recipientName,
                              recipientAvatarColor: widget.recipientAvatarColor,
                              recipientId: widget.recipientId,
                              bytes: imgMsg.bytes,
                              onForward: () {
                                showForwardSheet(
                                  context: context,
                                  messageText: 'Photo',
                                  imageUrl: imgMsg.imageUrl,
                                );
                              },
                            );
                          }

                          // Document message
                          if (item.type == _ChatItemType.document) {
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

                          // Text message
                          final msgIndex = item.textIndex!;
                          final msg = _messages[msgIndex];

                          // Skip messages unsent "just for me"
                          if (_hiddenMessageIds.contains(msg.id)) {
                            return const SizedBox.shrink();
                          }

                          final showTimestamp = msgIndex == 0 ||
                              msg.timestamp
                                      .difference(
                                          _messages[msgIndex - 1].timestamp)
                                      .inMinutes >
                                  5;

                          final isHighlighted = _isSearching &&
                              _searchMatches.isNotEmpty &&
                              _currentMatchIndex >= 0 &&
                              _searchMatches[_currentMatchIndex] == msgIndex;

                          // Check if unsent for everyone
                          final isDeletedForEveryone = _deletedForEveryoneIds.contains(msg.id);

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
                                  reactions: _reactions[msg.id] ?? {},
                                  onTapReaction: (emoji) => _toggleReaction(msg.id, emoji),
                                  onReply: () => _startReply(msg),
                                  onCopy: () => _copyMessage(msg.message),
                                  onUnsend: msg.isMe ? () => _showUnsendDialog(msg) : null,
                                  onAvatarTap: msg.isMe ? null : () => _showMemberProfileSheet(context),
                                  replyTo: msg.replyToText,
                                  replyToSender: msg.replyToSender,
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
      backgroundColor: HuddlColors.white,
      elevation: 0,
      surfaceTintColor: HuddlColors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
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
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isRecipientTyping ? 'typing...' : 'Online',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: _isRecipientTyping
                        ? HuddlColors.teal
                        : HuddlColors.textHint,
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
          icon: const Icon(Icons.search, color: HuddlColors.textDark),
          onPressed: () => setState(() => _isSearching = true),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: HuddlColors.textDark),
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: HuddlColors.white,
          elevation: 8,
          onSelected: (value) {
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications muted')),
                );
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
                      size: 20, color: HuddlColors.textDark),
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
                  const Icon(Icons.person_outline, size: 20, color: HuddlColors.textDark),
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
                  const Icon(Icons.bookmark_outline, size: 20, color: HuddlColors.textDark),
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
                  const Icon(Icons.search, size: 20, color: HuddlColors.textDark),
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
                  const Icon(Icons.notifications_off_outlined, size: 20, color: HuddlColors.textDark),
                  const SizedBox(width: 12),
                  Text('Mute notifications',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  const SizedBox(width: 12),
                  Text('Delete conversation',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: HuddlColors.divider),
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: HuddlColors.white,
      elevation: 0,
      surfaceTintColor: HuddlColors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
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
        style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search messages...',
          hintStyle:
              GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
          border: InputBorder.none,
        ),
        onChanged: _performSearch,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: HuddlColors.divider),
      ),
    );
  }

  // ── Reply helpers ──────────────────────────────────────────────────
  void _startReply(DirectMessage msg) {
    setState(() => _replyingTo = msg);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  // ── Copy message ──────────────────────────────────────────────────
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

  // ── Member profile bottom sheet ────────────────────────────────
  void _showMemberProfileSheet(BuildContext context) {
    final photoUrl = getProfilePhotoForMember(widget.recipientId);
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
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
                  color: HuddlColors.divider,
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
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34C759),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Online',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: HuddlColors.textSecondary,
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
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _profileInfoRow(Icons.person_outline, 'Parent type', 'Mum'),
                    const Divider(height: 20, color: HuddlColors.divider),
                    _profileInfoRow(Icons.location_on_outlined, 'Area', 'Cambridge'),
                    const Divider(height: 20, color: HuddlColors.divider),
                    _profileInfoRow(Icons.child_care_outlined, 'Stage', 'Toddler (1-3 years)'),
                    const Divider(height: 20, color: HuddlColors.divider),
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
                        backgroundColor: Colors.red.withValues(alpha: 0.1),
                        foregroundColor: Colors.red,
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
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
        const Spacer(),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
      ],
    );
  }

  Widget _buildInputBar() {
    // Show blocked banner instead of input bar when user is blocked
    if (_isBlocked) {
      return Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: const BoxDecoration(
          color: HuddlColors.white,
          border: Border(top: BorderSide(color: HuddlColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.block, size: 20, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You have blocked ${widget.recipientName}. Unblock to send messages.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: HuddlColors.textSecondary,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply preview bar
        if (_replyingTo != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: HuddlColors.white,
              border: Border(
                top: BorderSide(color: HuddlColors.divider, width: 0.5),
                left: BorderSide(color: HuddlColors.primary, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.reply, size: 18, color: HuddlColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _replyingTo!.isMe ? 'You' : widget.recipientName,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                      Text(
                        _replyingTo!.message,
                        style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: HuddlColors.textHint),
                  onPressed: _cancelReply,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        // Attach menu now handled via bottom sheet (WhatsApp-style)
        // ── Main input row ─────────────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(
              8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
          decoration: const BoxDecoration(
            color: HuddlColors.white,
            border:
                Border(top: BorderSide(color: HuddlColors.divider, width: 0.5)),
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
                    color: HuddlColors.background,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: HuddlColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textHint),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    onTap: () {
                      // Focus text field
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
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
              ),
            ],
          ),
        ),
      ],
    );
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
                  color: HuddlColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose how you want to unsend this message.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textSecondary,
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
                    backgroundColor: Colors.red,
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
                    side: const BorderSide(color: HuddlColors.divider),
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
                        fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textHint)),
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
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello and start a conversation!',
            style:
                GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
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
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This will delete all messages in this conversation.',
          style: GoogleFonts.poppins(color: HuddlColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: HuddlColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              if (_conversationId != null) {
                await _dmService.deleteConversation(_conversationId!);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
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
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block, size: 32, color: Colors.red),
              ),
              const SizedBox(height: 18),
              Text(
                _isBlocked ? 'Unblock ${widget.recipientName}?' : 'Block ${widget.recipientName}?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: HuddlColors.textDark,
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
                  color: HuddlColors.textSecondary,
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
                        backgroundColor: Colors.red,
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
                          color: HuddlColors.white,
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
      backgroundColor: HuddlColors.white,
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
                  color: HuddlColors.divider,
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
                        color: HuddlColors.textDark,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${saved.length}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: HuddlColors.divider),
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
                            color: HuddlColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Text(
                            'You have no saved messages currently. Long press on any message to save it.',
                            style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary),
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
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16, color: HuddlColors.divider),
                    itemBuilder: (_, i) {
                      final msg = saved[i];
                      return ListTile(
                        leading: const Icon(Icons.bookmark, color: HuddlColors.primary, size: 20),
                        title: Text(
                          msg.message,
                          style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${msg.senderName} - ${_formatSavedDate(msg.timestamp)}',
                          style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: HuddlColors.textHint),
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
  // ── Interleaved list helpers ────────────────────────────────────────
  List<_ChatItem> get _sortedItems {
    final items = <_ChatItem>[];
    for (int i = 0; i < _messages.length; i++) {
      items.add(_ChatItem(type: _ChatItemType.text, textIndex: i, timestamp: _messages[i].timestamp));
    }
    for (int i = 0; i < _imageMessages.length; i++) {
      items.add(_ChatItem(type: _ChatItemType.image, imageIndex: i, timestamp: _imageMessages[i].timestamp));
    }
    for (int i = 0; i < _documentMessages.length; i++) {
      items.add(_ChatItem(type: _ChatItemType.document, docIndex: i, timestamp: _documentMessages[i].timestamp));
    }
    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return items;
  }

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
    _addImageMessage(attachment);
  }

  Future<void> _handleGalleryPick() async {
    final attachments = await _mediaService.pickMultipleImages();
    if (attachments.isEmpty || !mounted) return;
    for (final att in attachments) {
      _addImageMessage(att);
    }
  }

  void _addImageMessage(MediaAttachment att) {
    // Use the file path or object URL for display
    final url = att.filePath ?? 'local_image_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _imageMessages.add(_ImageChatMessage(
        imageUrl: url,
        isMe: true,
        timestamp: DateTime.now(),
        bytes: att.bytes,
      ));
    });
    _scrollToBottom(animate: true);
  }

  Future<void> _handleDocumentPick() async {
    final attachment = await _mediaService.pickDocument();
    if (attachment == null || !mounted) return;
    setState(() {
      _documentMessages.add(_DocumentChatMessage(
        fileName: attachment.fileName ?? 'Unknown file',
        fileSize: attachment.fileSize,
        isMe: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom(animate: true);
  }

  void _handleLocationShare() {
    if (!mounted) return;
    // Show a styled location-sharing preview
    setState(() {
      _imageMessages.add(_ImageChatMessage(
        imageUrl: 'location_pin',
        isMe: true,
        timestamp: DateTime.now(),
        isLocationPin: true,
      ));
    });
    _scrollToBottom(animate: true);
  }

  void _handleContactShare() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Contact sharing coming soon'),
        backgroundColor: HuddlColors.textSecondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Emoji reactions ────────────────────────────────────────────────────
  Future<void> _showEmojiPicker(String messageId) async {
    final emoji = await showEmojiReactionPicker(context);
    if (emoji != null && mounted) {
      _toggleReaction(messageId, emoji);
    }
  }

  void _toggleReaction(String messageId, String emoji) {
    setState(() {
      final msgReactions = _reactions[messageId] ?? {};
      final current = msgReactions[emoji] ?? 0;
      if (current > 0) {
        // Same emoji tapped again - remove it
        msgReactions.remove(emoji);
      } else {
        // New emoji - clear all previous reactions (replace behavior) and set new one
        msgReactions.clear();
        msgReactions[emoji] = 1;
      }
      if (msgReactions.isEmpty) {
        _reactions.remove(messageId);
      } else {
        _reactions[messageId] = msgReactions;
      }
    });
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
  final VoidCallback? onReply;
  final VoidCallback? onCopy;
  final VoidCallback? onUnsend;
  final VoidCallback? onAvatarTap;
  final Map<String, int> reactions;
  final void Function(String emoji)? onTapReaction;
  final String? replyTo;
  final String? replyToSender;

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
    this.onReply,
    this.onCopy,
    this.onUnsend,
    this.onAvatarTap,
    this.reactions = const {},
    this.onTapReaction,
    this.replyTo,
    this.replyToSender,
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
                          ? HuddlColors.yellowLight
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
                        // Reply preview
                        if (replyTo != null && replyTo!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? HuddlColors.primary.withValues(alpha: 0.08)
                                  : HuddlColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(color: HuddlColors.primary, width: 3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  replyToSender ?? '',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.primary,
                                  ),
                                ),
                                Text(
                                  replyTo!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: HuddlColors.textSecondary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        // Message text (with search highlighting)
                        searchQuery.isNotEmpty
                            ? _buildHighlightedText(message.message, searchQuery)
                            : Text(
                                message.message,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: HuddlColors.textDark,
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
                                color: HuddlColors.textHint,
                              ),
                            ),
                            if (isSaved) ...[
                              Icon(Icons.bookmark, size: 12,
                                  color: HuddlColors.primary.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                            ],
                            if (isMe) ...[
                              const SizedBox(width: 4),
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: HuddlColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 16, color: HuddlColors.textHint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message.message,
                        style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary),
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
                          color: HuddlColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: HuddlColors.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: HuddlColors.divider),
              ListTile(
                leading: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_outline,
                  color: isSaved ? HuddlColors.primary : HuddlColors.textDark,
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
                leading: const Icon(Icons.copy_outlined, color: HuddlColors.textDark),
                title: Text('Copy text',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onCopy?.call();
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply_outlined, color: HuddlColors.textDark),
                title: Text('Reply',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onReply?.call();
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward_outlined, color: HuddlColors.textDark),
                title: Text('Forward',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(c);
                  onForward?.call();
                },
              ),
              if (onUnsend != null)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: Text('Unsend message',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w500, color: Colors.red)),
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

  Widget _buildHighlightedText(String text, String query) {
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
        style: const TextStyle(
          backgroundColor: Color(0xFFFFEB3B),
          fontWeight: FontWeight.w600,
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
            color: HuddlColors.background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: Border.all(color: HuddlColors.divider, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 14, color: HuddlColors.textHint),
              const SizedBox(width: 6),
              Text(
                'This message was deleted',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: HuddlColors.textHint,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(timestamp),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: HuddlColors.textHint,
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
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 14, color: HuddlColors.textHint);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: HuddlColors.textHint);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: HuddlColors.textHint);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: HuddlColors.blue);
      case MessageStatus.error:
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
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
    return Padding(
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
              color: HuddlColors.white,
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
                        color: HuddlColors.textHint
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECIPIENT AVATAR — circle with initials
// ═══════════════════════════════════════════════════════════════════════════════

class _RecipientAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final color = _colorFromHex(colorHex);
    final photoUrl = memberId != null ? getProfilePhotoForMember(memberId!) : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl != null
          ? Image.network(
              photoUrl,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
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
          const Expanded(child: Divider(color: HuddlColors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(timestamp),
              style: GoogleFonts.poppins(
                  fontSize: 11, color: HuddlColors.textHint),
            ),
          ),
          const Expanded(child: Divider(color: HuddlColors.divider)),
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
// IMAGE CHAT MESSAGE — lightweight model for locally-added images
// ═══════════════════════════════════════════════════════════════════════════════

class _ImageChatMessage {
  final String imageUrl;
  final bool isMe;
  final DateTime timestamp;
  final Uint8List? bytes;
  final bool isLocationPin;

  const _ImageChatMessage({
    required this.imageUrl,
    required this.isMe,
    required this.timestamp,
    this.bytes,
    this.isLocationPin = false,
  });
}

class _DocumentChatMessage {
  final String fileName;
  final int? fileSize;
  final bool isMe;
  final DateTime timestamp;

  const _DocumentChatMessage({
    required this.fileName,
    this.fileSize,
    required this.isMe,
    required this.timestamp,
  });
}

enum _ChatItemType { text, image, document }

class _ChatItem {
  final _ChatItemType type;
  final int? textIndex;
  final int? imageIndex;
  final int? docIndex;
  final DateTime timestamp;

  const _ChatItem({
    required this.type,
    this.textIndex,
    this.imageIndex,
    this.docIndex,
    required this.timestamp,
  });
}

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
  final Uint8List? bytes;

  const _ImageBubble({
    required this.imageUrl,
    required this.isMe,
    required this.timestamp,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.recipientId,
    this.onForward,
    this.bytes,
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
                    child: bytes != null
                        ? Image.memory(
                            bytes!,
                            fit: BoxFit.cover,
                            width: 240,
                            height: 240,
                            errorBuilder: (_, __, ___) => _brokenImage(),
                          )
                        : Image.network(
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
        child: const Icon(Icons.broken_image, color: HuddlColors.textHint, size: 48),
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

  const _LocationBubble({
    required this.isMe,
    required this.timestamp,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.recipientId,
  });

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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFFFF3ED) : HuddlColors.white,
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
                  // Map-like header
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Grid lines to simulate map
                        Opacity(
                          opacity: 0.15,
                          child: Column(
                            children: List.generate(6, (_) => Expanded(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
                                ),
                              ),
                            )),
                          ),
                        ),
                        const Icon(Icons.location_on, size: 40, color: Color(0xFFE53935)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: HuddlColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Shared location',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textDark,
                            ),
                          ),
                        ),
                        Text(
                          _formatTime(timestamp),
                          style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint),
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
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
