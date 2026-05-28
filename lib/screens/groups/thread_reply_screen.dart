import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../services/onboarding_data_service.dart';
import '../../constants/app_text_styles.dart';

// ── Thread reply data model ─────────────────────────────────────────────────
class ThreadReply {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String message;
  final DateTime timestamp;
  final bool isMe;

  ThreadReply({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.message,
    required this.timestamp,
    this.isMe = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'senderAvatar': senderAvatar,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isMe': isMe,
  };

  factory ThreadReply.fromJson(Map<String, dynamic> json) => ThreadReply(
    id: json['id'] as String? ?? '',
    senderId: json['senderId'] as String? ?? '',
    senderName: json['senderName'] as String? ?? '',
    senderAvatar: json['senderAvatar'] as String? ?? '',
    message: json['message'] as String? ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    isMe: json['isMe'] as bool? ?? false,
  );
}

// ── Thread reply screen ─────────────────────────────────────────────────────
class ThreadReplyScreen extends StatefulWidget {
  final ChatMessage rootMessage;
  final String groupId;
  final String groupName;
  final List<ThreadReply> existingReplies;
  final void Function(ThreadReply reply) onReplySent;

  const ThreadReplyScreen({
    super.key,
    required this.rootMessage,
    required this.groupId,
    required this.groupName,
    this.existingReplies = const [],
    required this.onReplySent,
  });

  @override
  State<ThreadReplyScreen> createState() => _ThreadReplyScreenState();
}

class _ThreadReplyScreenState extends State<ThreadReplyScreen> {
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  late List<ThreadReply> _replies;
  String _userName = 'You';

  @override
  void initState() {
    super.initState();
    _replies = List.from(widget.existingReplies);
    _initUser();
  }

  Future<void> _initUser() async {
    await _onboardingService.initialize();
    if (mounted) {
      setState(() {
        _userName = _onboardingService.name ?? 'You';
      });
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    final reply = ThreadReply(
      id: 'thread_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'current_user',
      senderName: _userName,
      senderAvatar: '',
      message: text,
      timestamp: DateTime.now(),
      isMe: true,
    );

    setState(() {
      _replies.add(reply);
    });
    _replyController.clear();
    widget.onReplySent(reply);

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

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDateSeparator(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today) return 'Today';
    if (msgDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final senderName = widget.rootMessage.isMe ? 'You' : widget.rootMessage.senderName;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: HuddlColors.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reply to $senderName',
          style: HuddlText.body(weight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: Column(
        children: [
          // ── Messages area ──────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                // ── Original message (root) ──────────────────────────
                _buildRootMessage(),

                // ── Reply count + date separator ─────────────────────
                if (_replies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '${_replies.length} ${_replies.length == 1 ? 'reply' : 'replies'}',
                        style: HuddlText.caption(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(height: 0.5, color: context.hc.divider),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatDateSeparator(_replies.first.timestamp),
                        style: HuddlText.caption(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Thread replies ───────────────────────────────────
                ..._replies.map((reply) => _buildReplyBubble(reply)),
              ],
            ),
          ),

          // ── Input bar ──────────────────────────────────────────────
          _buildInputBar(),
        ],
      ),
    );
  }

  /// Original message displayed at the top of the thread
  Widget _buildRootMessage() {
    final isMe = widget.rootMessage.isMe;

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              widget.rootMessage.senderName,
              style: HuddlText.caption(),
            ),
          ),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? HuddlColors.primary.withValues(alpha: 0.10) : HuddlColors.white,
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
                Text(
                  widget.rootMessage.message,
                  style: HuddlText.body(color: context.hc.textPrimary),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.rootMessage.timestamp),
                      style: HuddlText.label(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Individual reply bubble in the thread
  Widget _buildReplyBubble(ThreadReply reply) {
    final isMe = reply.isMe;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4),
              child: Text(
                reply.senderName,
                style: HuddlText.caption(),
              ),
            ),
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: () => _showReplyActions(context, reply),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe ? HuddlColors.primary.withValues(alpha: 0.10) : HuddlColors.white,
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
                    Text(
                      reply.message,
                      style: HuddlText.body(color: context.hc.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(reply.timestamp),
                          style: HuddlText.label(),
                        ),
                      ],
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

  void _showReplyActions(BuildContext context, ThreadReply reply) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => SafeArea(
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
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.copy_outlined, color: context.hc.textPrimary),
              title: Text('Copy text',
                  style: HuddlText.body()),
              onTap: () {
                Navigator.pop(c);
                Clipboard.setData(ClipboardData(text: reply.message));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Message copied'),
                      ],
                    ),
                    backgroundColor: HuddlColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Input bar at the bottom — "Reply in thread..."
  Widget _buildInputBar() {
    return Container(
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
              color: HuddlColors.nearBlack,
            ),
            onPressed: () {
              // Placeholder for attachment in thread
            },
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: context.hc.scaffold,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _replyController,
                focusNode: _focusNode,
                textCapitalization: TextCapitalization.sentences,
                textAlignVertical: TextAlignVertical.center,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                style: HuddlText.body(color: context.hc.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Reply in thread...',
                  hintStyle:
                      HuddlText.body(color: context.hc.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => _sendReply(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _sendReply,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: HuddlColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, size: 18, color: HuddlColors.white),
            ),
          ),
        ],
      ),
    );
  }
}
