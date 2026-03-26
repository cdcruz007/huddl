import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/direct_message.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const Color _kMyBubble = Color(0xFFFFF3ED);

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

  List<DirectMessage> _messages = [];
  bool _isLoading = true;
  String? _conversationId;
  String _userName = 'You';
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchMatches = []; // indices of matching messages
  int _currentMatchIndex = -1;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _loadData();
    _dmService.addListener(_onServiceUpdate);
    _savedMessageService.initialize();
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
    );

    setState(() => _messages.add(msg));
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
                : _messages.isEmpty
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
                                color: widget.recipientAvatarColor);
                          }

                          final msg = _messages[index];
                          final showTimestamp = index == 0 ||
                              msg.timestamp
                                      .difference(
                                          _messages[index - 1].timestamp)
                                      .inMinutes >
                                  5;

                          final isHighlighted = _isSearching &&
                              _searchMatches.isNotEmpty &&
                              _currentMatchIndex >= 0 &&
                              _searchMatches[_currentMatchIndex] == index;

                          return Column(
                            children: [
                              if (showTimestamp)
                                _TimestampDivider(timestamp: msg.timestamp),
                              _DMBubble(
                                message: msg,
                                recipientName: widget.recipientName,
                                recipientAvatarColor:
                                    widget.recipientAvatarColor,
                                isHighlighted: isHighlighted,
                                searchQuery: _searchQuery,
                                isSaved: _savedMessageService.isMessageSaved(msg.id),
                                onSave: () => _saveMessage(msg),
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
              case 'search':
                setState(() => _isSearching = true);
                break;
              case 'mute':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications muted')),
                );
                break;
              case 'saved':
                Navigator.pop(context);
                break;
              case 'delete':
                _confirmDeleteConversation();
                break;
            }
          },
          itemBuilder: (context) => [
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

  Widget _buildInputBar() {
    return Container(
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
            icon: const Icon(Icons.add_circle_outline,
                color: HuddlColors.primary),
            onPressed: () {},
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
  final bool isHighlighted;
  final String searchQuery;
  final bool isSaved;
  final VoidCallback? onSave;

  const _DMBubble({
    required this.message,
    required this.recipientName,
    required this.recipientAvatarColor,
    this.isHighlighted = false,
    this.searchQuery = '',
    this.isSaved = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return GestureDetector(
      onLongPress: () => _showMessageActions(context),
      child: Padding(
      padding: EdgeInsets.only(
        top: 4,
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
              size: 32,
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                onTap: () => Navigator.pop(c),
              ),
              ListTile(
                leading: const Icon(Icons.reply_outlined, color: HuddlColors.textDark),
                title: Text('Reply',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.pop(c),
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
  const _TypingIndicator({required this.name, required this.color});

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
              name: widget.name, colorHex: widget.color, size: 32),
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
  final double size;

  const _RecipientAvatar({
    required this.name,
    required this.colorHex,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(colorHex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Center(
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

// ── Utility ───────────────────────────────────────────────────────────────
Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
