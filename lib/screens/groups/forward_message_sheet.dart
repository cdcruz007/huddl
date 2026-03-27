import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/invitation_service.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import 'dm_chat_screen.dart' show getProfilePhotoForMember;

/// Represents a forwarding target — either a DM contact or a group.
class _ForwardTarget {
  final String id;
  final String name;
  final String? avatarUrl;
  final String avatarColor;
  final bool isGroup;
  final String? groupImageUrl;

  const _ForwardTarget({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.avatarColor = '#FF975C',
    this.isGroup = false,
    this.groupImageUrl,
  });
}

/// State of a forward-send for a target.
enum _SendState { idle, sending, sent, undo }

/// Shows a bottom sheet for forwarding a message/photo/document to
/// one or more DM contacts or groups.
///
/// Matches the design reference: white sheet, "Send to" header,
/// image thumbnail preview, search field, RECENTS list, orange
/// SEND button that becomes UNDO (5 sec) then SENT.
Future<void> showForwardSheet({
  required BuildContext context,
  required String messageText,
  String? imageUrl,
  String? documentName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForwardSheet(
      messageText: messageText,
      imageUrl: imageUrl,
      documentName: documentName,
    ),
  );
}

class _ForwardSheet extends StatefulWidget {
  final String messageText;
  final String? imageUrl;
  final String? documentName;

  const _ForwardSheet({
    required this.messageText,
    this.imageUrl,
    this.documentName,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final DMService _dmService = DMService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  List<_ForwardTarget> _allTargets = [];
  List<_ForwardTarget> _filtered = [];
  String _query = '';
  bool _loading = true;

  /// Per-target send state, keyed by target.id
  final Map<String, _SendState> _sendStates = {};
  final Map<String, Timer?> _undoTimers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final t in _undoTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    await _dmService.initialize();
    await _onboarding.initialize();

    final targets = <_ForwardTarget>[];

    // Recent DM conversations first
    for (final conv in _dmService.conversations) {
      targets.add(_ForwardTarget(
        id: conv.recipientId,
        name: conv.recipientName,
        avatarUrl: getProfilePhotoForMember(conv.recipientId),
        avatarColor: conv.recipientAvatarColor,
      ));
    }

    // Borough members that aren't already in conversations
    final existingIds = targets.map((t) => t.id).toSet();
    final members = InvitationService.getBoroughMembers(null);
    for (final m in members) {
      if (!existingIds.contains(m.id)) {
        targets.add(_ForwardTarget(
          id: m.id,
          name: m.name,
          avatarUrl: getProfilePhotoForMember(m.id),
        ));
      }
    }

    // Joined groups
    final invService = InvitationService();
    await invService.initialize();
    for (final g in invService.joinedGroups) {
      targets.add(_ForwardTarget(
        id: g.id,
        name: g.name,
        isGroup: true,
        groupImageUrl: g.imageUrl,
      ));
    }

    setState(() {
      _allTargets = targets;
      _filtered = List.from(targets);
      _loading = false;
    });
  }

  void _applyFilter(String q) {
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _filtered = List.from(_allTargets);
      } else {
        final lower = q.toLowerCase();
        _filtered = _allTargets
            .where((t) => t.name.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  void _onSend(_ForwardTarget target) {
    setState(() => _sendStates[target.id] = _SendState.sending);

    // Simulate send
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _sendStates[target.id] = _SendState.undo);

      // Start 5-second undo window
      _undoTimers[target.id]?.cancel();
      _undoTimers[target.id] = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _sendStates[target.id] = _SendState.sent);
          // Actually forward the message (simulate)
          _doForward(target);
        }
      });
    });
  }

  void _onUndo(_ForwardTarget target) {
    _undoTimers[target.id]?.cancel();
    setState(() => _sendStates[target.id] = _SendState.idle);
  }

  Future<void> _doForward(_ForwardTarget target) async {
    if (target.isGroup) return; // Group forwarding is simulated
    // Forward to DM
    final conv = await _dmService.getOrCreateConversation(
      recipientId: target.id,
      recipientName: target.name,
      avatarColor: target.avatarColor,
    );
    final userName = _onboarding.name ?? 'You';
    String fwdText = widget.messageText;
    if (widget.imageUrl != null) {
      fwdText = '[Forwarded image] ${widget.messageText}';
    } else if (widget.documentName != null) {
      fwdText =
          '[Forwarded document: ${widget.documentName}] ${widget.messageText}';
    }
    await _dmService.sendMessage(
      conversationId: conv.id,
      message: fwdText,
      senderName: userName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ───────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: HuddlColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // ── Header — "Send to" + Cancel ──────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Send to',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Image / message preview ─────────────────────
          _buildPreview(),
          const SizedBox(height: 12),

          // ── Search bar ─────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 44,
            decoration: BoxDecoration(
              color: HuddlColors.background,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: HuddlColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'Search list',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textHint),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: _applyFilter,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      _applyFilter('');
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close,
                          size: 18, color: HuddlColors.textHint),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── "RECENTS" label ────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RECENTS',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textHint,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),

          // ── Contact/group list ─────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: HuddlColors.primary))
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No contacts found',
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: HuddlColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.only(bottom: bottomPad + 20),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 72,
                          color: HuddlColors.divider,
                        ),
                        itemBuilder: (context, index) {
                          final target = _filtered[index];
                          final state =
                              _sendStates[target.id] ?? _SendState.idle;
                          return _ForwardContactTile(
                            target: target,
                            sendState: state,
                            onSend: () => _onSend(target),
                            onUndo: () => _onUndo(target),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// Builds the preview section — image thumbnail + caption, or text preview.
  Widget _buildPreview() {
    // If forwarding an image, show the image thumbnail (matching the design)
    if (widget.imageUrl != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: HuddlColors.peachLight,
                  child: const Icon(Icons.image,
                      size: 24, color: HuddlColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  if (widget.messageText.isNotEmpty &&
                      widget.messageText != 'Photo')
                    Text(
                      widget.messageText,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // If forwarding a document
    if (widget.documentName != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.insert_drive_file,
                  size: 20, color: HuddlColors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.documentName!,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: HuddlColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Text message preview
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HuddlColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 16, color: HuddlColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.messageText,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: HuddlColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FORWARD CONTACT TILE — avatar + name + SEND/UNDO/SENT button
// ═══════════════════════════════════════════════════════════════════════════════

class _ForwardContactTile extends StatelessWidget {
  final _ForwardTarget target;
  final _SendState sendState;
  final VoidCallback onSend;
  final VoidCallback onUndo;

  const _ForwardContactTile({
    required this.target,
    required this.sendState,
    required this.onSend,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: HuddlColors.white,
      child: Row(
        children: [
          // Avatar
          _buildAvatar(),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (target.isGroup)
                  Text(
                    'Group',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                  ),
              ],
            ),
          ),
          // Send / Undo / Sent button
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const size = 44.0;

    if (target.isGroup) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: HuddlColors.peachLight,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: target.groupImageUrl != null &&
                target.groupImageUrl!.startsWith('http')
            ? Image.network(
                target.groupImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.people,
                    size: 22, color: HuddlColors.primary),
              )
            : const Icon(Icons.people, size: 22, color: HuddlColors.primary),
      );
    }

    final color = _colorFromHex(target.avatarColor);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: target.avatarUrl != null
          ? Image.network(
              target.avatarUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
    );
  }

  Widget _buildActionButton() {
    switch (sendState) {
      case _SendState.idle:
        return _pill(
          label: 'SEND',
          color: HuddlColors.primary,
          textColor: HuddlColors.white,
          onTap: onSend,
        );
      case _SendState.sending:
        return const SizedBox(
          width: 72,
          height: 34,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HuddlColors.primary,
              ),
            ),
          ),
        );
      case _SendState.undo:
        return _pill(
          label: 'UNDO',
          color: HuddlColors.primary,
          textColor: HuddlColors.white,
          onTap: onUndo,
        );
      case _SendState.sent:
        return _pill(
          label: 'SENT',
          color: HuddlColors.primary.withValues(alpha: 0.12),
          textColor: HuddlColors.primary,
        );
    }
  }

  Widget _pill({
    required String label,
    required Color color,
    required Color textColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(17),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
