import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/media_attach_service.dart';

/// A chat bubble that displays a document/file attachment, styled like
/// WhatsApp's document message UI.
///
/// States:
///  • Normal    — icon + filename + size + forward button + optional open tap
///  • Uploading — spinner replaces the forward button; tap is disabled
///  • Error     — red retry banner below the card; [onRetry] callback exposed
class DocumentBubble extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final bool isMe;
  final DateTime timestamp;

  /// Called when the user taps the card body to open / download the file.
  /// Pass null while the file URL is unavailable (uploading / no URL).
  final VoidCallback? onTap;

  /// Called when the user taps the forward icon.
  final VoidCallback? onForward;

  /// True while the upload is still in progress.
  /// Shows a circular progress indicator instead of the forward icon.
  final bool isUploading;

  /// Non-null when the upload failed.  Shows a retry banner at the bottom
  /// of the bubble.  [onRetry] is called when the user taps it.
  final String? uploadError;

  /// Called when the user taps the retry banner after a failed upload.
  final VoidCallback? onRetry;

  const DocumentBubble({
    super.key,
    required this.fileName,
    this.fileSize,
    required this.isMe,
    required this.timestamp,
    this.onTap,
    this.onForward,
    this.isUploading = false,
    this.uploadError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final icon = MediaAttachService.getDocumentIcon(fileName);
    final ext = fileName.split('.').last.toUpperCase();
    final sizeStr = fileSize != null
        ? MediaAttachService.formatFileSize(fileSize!)
        : '';

    return GestureDetector(
      onTap: isUploading ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe
              ? HuddlColors.primary.withValues(alpha: 0.10)
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
                  // File type emoji icon
                  Text(icon, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  // Filename + extension / size
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
                  const SizedBox(width: 6),
                  // Right-side action: spinner | forward icon
                  if (isUploading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          HuddlColors.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  else if (onForward != null)
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

            // ── Upload-error retry banner ─────────────────────────
            if (uploadError != null && uploadError!.isNotEmpty) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded,
                          size: 14, color: Colors.red),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          uploadError!,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

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
