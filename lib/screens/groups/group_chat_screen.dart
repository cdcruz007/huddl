import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../models/direct_message.dart';
import '../../services/invitation_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/saved_message_service.dart';

// ── Design tokens — use HuddlColors as single source of truth ────────
const Color _kMyBubble = Color(0xFFFFF3ED);

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupImageUrl;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupImageUrl,
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

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  List<int> _searchMatches = [];
  int _currentMatchIndex = -1;
  // Simulated message status progression for user messages
  final Map<String, MessageStatus> _messageStatuses = {};

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    await _invitationService.initialize();
    await _onboardingService.initialize();
    await _savedMessageService.initialize();

    // Generate demo messages
    _messages = _generateDemoMessages();

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

    setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _messages.add(ChatMessage(
        id: msgId,
        senderId: 'current_user',
        senderName: _onboardingService.name ?? 'You',
        senderAvatar: '',
        message: text,
        timestamp: DateTime.now(),
        isMe: true,
      ));
      _messageStatuses[msgId] = MessageStatus.sending;
    });

    _messageController.clear();

    // Simulate status progression: sending -> sent -> delivered -> read
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _messageStatuses[msgId] = MessageStatus.sent);
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _messageStatuses[msgId] = MessageStatus.delivered);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _messageStatuses[msgId] = MessageStatus.read);
    });

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

  // ── Save message ──────────────────────────────────────────────────────
  void _saveMessage(ChatMessage msg) {
    if (_savedMessageService.isMessageSaved(msg.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message already saved'),
          backgroundColor: HuddlColors.textHint,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _savedMessageService.saveGroupMessage(
      messageId: msg.id,
      message: msg.message,
      senderName: msg.senderName,
      timestamp: msg.timestamp,
      groupId: widget.groupId,
      groupName: widget.groupName,
      groupImageUrl: widget.groupImageUrl,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.bookmark_added, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Message saved to Saved tab')),
          ],
        ),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
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
                        final userName = _onboardingService.name ?? 'You';
                        await _invitationService.leaveGroup(widget.groupId, userName);
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
                    child: CircularProgressIndicator(color: HuddlColors.primary))
                : _messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];

                          // System messages (join/leave)
                          if (msg.isSystem) {
                            return _SystemMessageBubble(message: msg);
                          }

                          final showAvatar = index == 0 ||
                              _messages[index - 1].senderId != msg.senderId ||
                              _messages[index - 1].isSystem;
                          final showTimestamp = index == 0 ||
                              msg.timestamp
                                      .difference(_messages[index - 1].timestamp)
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
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
          border: InputBorder.none,
        ),
        onChanged: _performGroupSearch,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: HuddlColors.divider),
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
      title: GestureDetector(
        onTap: () {
          Navigator.pushNamed(context, '/group_details', arguments: {
            'groupId': widget.groupId,
            'groupName': widget.groupName,
            'groupImageUrl': widget.groupImageUrl,
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
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Tap here for group info',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
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
          icon: const Icon(Icons.search, color: HuddlColors.textDark),
          onPressed: () => setState(() => _isSearching = true),
        ),
        // 3-dot popup menu matching the screenshot design
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: HuddlColors.textDark),
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: HuddlColors.white,
          elevation: 8,
          onSelected: (value) {
            switch (value) {
              case 'leave':
                _showLeaveGroupDialog();
                break;
              case 'details':
                Navigator.pushNamed(context, '/group_details', arguments: {
                  'groupId': widget.groupId,
                  'groupName': widget.groupName,
                  'groupImageUrl': widget.groupImageUrl,
                });
                break;
              case 'saved':
                // Navigate to Groups screen, Saved tab
                Navigator.pop(context);
                // We'll signal the parent to switch to saved tab
                Navigator.pushReplacementNamed(context, '/home', arguments: {
                  'initialTab': 2, // Groups tab
                  'groupsSubTab': 2, // Saved sub-tab
                });
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'leave',
              child: Row(
                children: [
                  const Icon(Icons.exit_to_app, size: 20, color: HuddlColors.textDark),
                  const SizedBox(width: 12),
                  Text(
                    'Leave group',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'details',
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: HuddlColors.textDark),
                  const SizedBox(width: 12),
                  Text(
                    'Group details',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'saved',
              child: Row(
                children: [
                  const Icon(Icons.bookmark_outline, size: 20, color: HuddlColors.textDark),
                  const SizedBox(width: 12),
                  Text(
                    'Saved messages',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
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
        child: Container(height: 1, color: HuddlColors.divider),
      ),
    );
  }

  Widget _buildGroupAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: HuddlColors.peachLight,
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.groupImageUrl.startsWith('assets/')
          ? Image.asset(
              widget.groupImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.people,
                  size: size * 0.5, color: HuddlColors.primary),
            )
          : widget.groupImageUrl.startsWith('http')
              ? Image.network(
                  widget.groupImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.people,
                      size: size * 0.5, color: HuddlColors.primary),
                )
              : widget.groupImageUrl.startsWith('data:')
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
    return Container(
      padding: EdgeInsets.fromLTRB(
          8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: HuddlColors.white,
        border: Border(top: BorderSide(color: HuddlColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: HuddlColors.primary),
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
                style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle:
                      GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
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
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Say hello to the group!',
            style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
          ),
        ],
      ),
    );
  }

  // ── Demo messages ───────────────────────────────────────────────────────
  List<ChatMessage> _generateDemoMessages() {
    final now = DateTime.now();
    final avatarColors = [
      '#FF975C',
      '#3580F0',
      '#199A85',
      '#A16AE9',
      '#5B9DFF',
      '#E8A838'
    ];

    return [
      ChatMessage(
        id: 'msg_1',
        senderId: 'user_emma',
        senderName: 'Emma',
        senderAvatar: avatarColors[0],
        message:
            'Good morning everyone! Has anyone tried the new cafe near the river?',
        timestamp: now.subtract(const Duration(hours: 2, minutes: 30)),
      ),
      ChatMessage(
        id: 'msg_2',
        senderId: 'user_sophie',
        senderName: 'Sophie',
        senderAvatar: avatarColors[1],
        message:
            'Yes! We went last weekend. They have a great kids\' menu and a lovely play area outside.',
        timestamp: now.subtract(const Duration(hours: 2, minutes: 25)),
      ),
      ChatMessage(
        id: 'msg_3',
        senderId: 'user_kate',
        senderName: 'Kate',
        senderAvatar: avatarColors[2],
        message: 'That sounds lovely! Is it buggy-friendly?',
        timestamp: now.subtract(const Duration(hours: 2, minutes: 20)),
      ),
      ChatMessage(
        id: 'msg_4',
        senderId: 'user_sophie',
        senderName: 'Sophie',
        senderAvatar: avatarColors[1],
        message:
            'Absolutely! Wide doors, ramp access, and they even have highchairs.',
        timestamp: now.subtract(const Duration(hours: 2, minutes: 18)),
      ),
      ChatMessage(
        id: 'msg_5',
        senderId: 'user_lucy',
        senderName: 'Lucy',
        senderAvatar: avatarColors[3],
        message:
            'Anyone fancy a group outing there this Thursday? Weather looks good!',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 45)),
      ),
      ChatMessage(
        id: 'msg_6',
        senderId: 'user_emma',
        senderName: 'Emma',
        senderAvatar: avatarColors[0],
        message: 'Count me in! What time works for everyone?',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 40)),
      ),
      ChatMessage(
        id: 'msg_7',
        senderId: 'user_james',
        senderName: 'James',
        senderAvatar: avatarColors[4],
        message: '10:30am would be ideal before the lunch rush.',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 35)),
      ),
      ChatMessage(
        id: 'msg_8',
        senderId: 'user_anna',
        senderName: 'Anna',
        senderAvatar: avatarColors[5],
        message: 'Perfect timing! See you all there.',
        timestamp: now.subtract(const Duration(hours: 1, minutes: 30)),
      ),
    ];
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
            color: HuddlColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: HuddlColors.divider,
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
                    color: HuddlColors.textSecondary,
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

  const _ChatBubble({
    required this.message,
    required this.showAvatar,
    this.messageStatus,
    this.isHighlighted = false,
    this.searchQuery = '',
    this.isSaved = false,
    this.onAvatarTap,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return GestureDetector(
      onLongPress: () => _showMessageActions(context),
      child: Padding(
        padding: EdgeInsets.only(
          top: showAvatar ? 12 : 2,
          bottom: 2,
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
                    showTapHint: onAvatarTap != null,
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
                          ? const Color(0xFFFFF7C9)
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
                                color: HuddlColors.textHint,
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
              // Message preview
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
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textSecondary,
                        ),
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
              ListTile(
                leading: const Icon(Icons.forward_outlined, color: HuddlColors.textDark),
                title: Text('Forward',
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

/// Message status icon for group chat messages
class _GroupMessageStatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _GroupMessageStatusIcon({required this.status});

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

class _SenderAvatar extends StatelessWidget {
  final String colorHex;
  final String name;
  final bool showTapHint;

  const _SenderAvatar({
    required this.colorHex,
    required this.name,
    this.showTapHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(colorHex);
    return Stack(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: showTapHint
                ? Border.all(color: color.withValues(alpha: 0.4), width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
        if (showTapHint)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: HuddlColors.white, width: 1.5),
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
          const Expanded(child: Divider(color: HuddlColors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formatDate(timestamp),
              style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint),
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
