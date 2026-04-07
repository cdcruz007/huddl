import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/media_attach_service.dart';

/// A chat bubble that displays a document/file attachment, styled like
/// WhatsApp's document message UI.
class DocumentBubble extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final bool isMe;
  final DateTime timestamp;
  final VoidCallback? onTap;
  final VoidCallback? onForward;

  const DocumentBubble({
    super.key,
    required this.fileName,
    this.fileSize,
    required this.isMe,
    required this.timestamp,
    this.onTap,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    final icon = MediaAttachService.getDocumentIcon(fileName);
    final ext = fileName.split('.').last.toUpperCase();
    final sizeStr = fileSize != null
        ? MediaAttachService.formatFileSize(fileSize!)
        : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe
              ? HuddlColors.peachLight
              : HuddlColors.white,
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
            // ── Document card ────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? HuddlColors.primary.withValues(alpha: 0.08)
                    : context.hc.scaffold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (sizeStr.isNotEmpty)
                          Text(
                            '$ext  $sizeStr',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: context.hc.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onForward != null)
                    GestureDetector(
                      onTap: onForward,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.shortcut_rounded,
                          size: 18,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // ── Timestamp ────────────────────────────────────────
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                _formatTime(timestamp),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: context.hc.textTertiary,
                ),
              ),
            ),
          ],
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
