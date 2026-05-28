import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../services/saved_message_service.dart';
import '../../constants/app_text_styles.dart';

/// A full-screen page showing saved messages filtered for a specific group.
/// Accessible from the 3-dot menu → "Saved messages" in a group chat.
class SavedMessagesForGroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const SavedMessagesForGroupScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<SavedMessagesForGroupScreen> createState() =>
      _SavedMessagesForGroupScreenState();
}

class _SavedMessagesForGroupScreenState
    extends State<SavedMessagesForGroupScreen> {
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

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saved Messages',
              style: HuddlText.heading(),
            ),
            Text(
              widget.groupName,
              style: HuddlText.caption(),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: HuddlColors.textTertiary))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final saved = _savedMessageService.getSavedForGroup(widget.groupId);

    if (saved.isEmpty) {
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
                  color: const Color(0xFFF7F7F7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bookmark_outline,
                    size: 40, color: HuddlColors.textDark),
              ),
              const SizedBox(height: 20),
              Text(
                'No saved messages',
                style: HuddlText.heading(),
              ),
              const SizedBox(height: 10),
              Text(
                'You have no saved messages currently.\nLong press on any message in this group to save it.',
                style: HuddlText.body(color: context.hc.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: saved.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, indent: 16, endIndent: 16, color: context.hc.divider),
      itemBuilder: (_, i) {
        final msg = saved[i];
        return Dismissible(
          key: Key(msg.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: HuddlColors.error.withValues(alpha: 0.1),
            child: const Icon(Icons.delete_outline, color: HuddlColors.error),
          ),
          onDismissed: (_) async {
            await _savedMessageService.unsaveMessage(msg.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Message removed from saved'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          },
          child: Container(
            color: context.hc.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender + time
                Row(
                  children: [
                    const Icon(Icons.bookmark,
                        size: 16, color: HuddlColors.textDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        msg.senderName,
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _formatDate(msg.savedAt),
                      style: HuddlText.caption(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Message text
                Text(
                  msg.message,
                  style: HuddlText.body(color: context.hc.textSecondary),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Original timestamp
                Text(
                  'Sent ${_formatDate(msg.timestamp)}',
                  style: HuddlText.caption(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
