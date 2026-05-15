import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/voice_message_service.dart';

/// A WhatsApp-style voice message bubble with play/pause, waveform, and timer.
/// Used in both DM and group chat screens.
class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds; // stored duration from Firestore
  final bool isMe;
  final DateTime timestamp;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isMe,
    required this.timestamp,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final _svc = VoiceMessageService.instance;
  StreamSubscription<String?>? _urlSub;
  StreamSubscription<Duration>? _posSub;

  bool _isPlaying = false;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _urlSub = _svc.playingUrlStream.listen((url) {
      if (!mounted) return;
      setState(() => _isPlaying = url == widget.audioUrl && _svc.isPlaying);
      if (url != widget.audioUrl) {
        setState(() => _position = Duration.zero);
      }
    });
    _posSub = _svc.positionStream.listen((pos) {
      if (!mounted) return;
      if (_svc.playingUrl == widget.audioUrl) {
        setState(() => _position = pos);
      }
    });
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      await _svc.togglePlayback(widget.audioUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not play voice message. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSecs = widget.durationSeconds;
    final elapsed = _position.inSeconds.clamp(0, totalSecs);
    final progress = totalSecs > 0 ? elapsed / totalSecs : 0.0;

    final bubbleColor = widget.isMe
        ? HuddlColors.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = widget.isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final iconColor = widget.isMe ? Colors.white : HuddlColors.primary;
    final waveColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.8)
        : HuddlColors.primary.withValues(alpha: 0.6);
    final waveActiveColor = widget.isMe ? Colors.white : HuddlColors.primary;
    final sliderActiveColor = widget.isMe ? Colors.white : HuddlColors.primary;
    final sliderInactiveColor = widget.isMe
        ? Colors.white.withValues(alpha: 0.4)
        : HuddlColors.primary.withValues(alpha: 0.3);

    final timeStr = _isPlaying || _position.inSeconds > 0
        ? VoiceMessageService.formatDurationObj(_position)
        : VoiceMessageService.formatDuration(totalSecs);

    return Container(
      constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Play / pause button — 48×48 hit area (iOS 44pt minimum)
              GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: iconColor.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: iconColor,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Waveform + slider
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Decorative waveform bars
                    SizedBox(
                      height: 20,
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          progress: progress,
                          activeColor: waveActiveColor,
                          inactiveColor: waveColor,
                        ),
                      ),
                    ),
                    // Thin progress slider
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: sliderActiveColor,
                        inactiveTrackColor: sliderInactiveColor,
                        thumbColor: sliderActiveColor,
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (v) async {
                          // Seek not supported in this version – just visual
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Timestamp + duration row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Duration / position
              Text(
                timeStr,
                style: GoogleFonts.poppins(fontSize: 10, color: textColor.withValues(alpha: 0.8)),
              ),
              // Message timestamp
              Text(
                _formatTime(widget.timestamp),
                style: GoogleFonts.poppins(fontSize: 10, color: textColor.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }
}

/// Custom painter that draws a faux waveform of bars.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  // Deterministic bar heights that look like audio waveform
  static const _barHeights = [
    0.3, 0.6, 0.9, 0.5, 0.8, 0.4, 1.0, 0.6, 0.7, 0.3,
    0.5, 0.9, 0.8, 0.4, 0.6, 0.3, 0.7, 1.0, 0.5, 0.8,
    0.4, 0.6, 0.3, 0.9, 0.5, 0.7, 0.4, 0.8, 0.6, 0.3,
  ];

  const _WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = _barHeights.length;
    final barW = (size.width - (count - 1) * 2) / count;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final frac = i / count;
      paint.color = frac <= progress ? activeColor : inactiveColor;
      final barH = _barHeights[i] * size.height;
      final top = (size.height - barH) / 2;
      final left = i * (barW + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barW.clamp(1, 6), barH),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}

/// Inline recording indicator shown in the input bar while recording.
class VoiceRecordingIndicator extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const VoiceRecordingIndicator({
    super.key,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<VoiceRecordingIndicator> createState() => _VoiceRecordingIndicatorState();
}

class _VoiceRecordingIndicatorState extends State<VoiceRecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _elapsed.inMinutes;
    final s = _elapsed.inSeconds % 60;
    final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          // Cancel button
          GestureDetector(
            onTap: widget.onCancel,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HuddlColors.error.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.delete_outline, color: HuddlColors.error, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          // Pulsing mic icon
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Icon(
              Icons.mic,
              color: Color.lerp(HuddlColors.error, HuddlColors.errorSoft, _pulseCtrl.value),
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          // Timer
          Text(
            timeStr,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: HuddlColors.error,
            ),
          ),
          const SizedBox(width: 8),
          // Swipe hint
          Expanded(
            child: Text(
              '< Swipe to cancel',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Send button
          GestureDetector(
            onTap: widget.onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: HuddlColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
