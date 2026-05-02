import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';


/// Singleton service that handles voice message recording, uploading, and playback.
/// Recording uses the `record` package (m4a/aac on device, webm on web).
/// Playback uses the `audioplayers` package.
class VoiceMessageService {
  VoiceMessageService._();
  static final VoiceMessageService instance = VoiceMessageService._();

  // ── Recording ────────────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordingStarted;
  String? _currentRecordingPath;

  // ── Playback ─────────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  String? _playingUrl;
  bool _isPlaying = false;
  final StreamController<String?> _playingUrlController =
      StreamController<String?>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  /// Stream of the URL currently playing (null = nothing playing).
  Stream<String?> get playingUrlStream => _playingUrlController.stream;

  /// Stream of current playback position.
  Stream<Duration> get positionStream => _positionController.stream;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get playingUrl => _playingUrl;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  bool _initialised = false;

  /// Call once after Firebase is ready (e.g. in main_shell initState).
  /// Idempotent — safe to call multiple times.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Configure audio context for speaker playback.
    //
    // iOS: `defaultToSpeaker` is only valid with `playAndRecord` category.
    // Using `playback` category alone is correct for playback-only and routes
    // audio to the speaker automatically (not the earpiece).
    // `allowBluetooth` requires `playAndRecord` or `record` — omit it here.
    if (!kIsWeb) {
      try {
        await _player.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {}, // no extra options — playback routes to speaker by default
            ),
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: false,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[VoiceMessageService] audio context error: $e');
      }
    }

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      // Emit the current URL so bubble widgets update their icon immediately
      _playingUrlController.add(_isPlaying ? _playingUrl : null);
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        _playingUrl = null;
      }
    });
    _player.onPositionChanged.listen((pos) {
      _positionController.add(pos);
    });
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _playingUrlController.close();
    _positionController.close();
  }

  // ── Recording API ─────────────────────────────────────────────────────────

  /// Request microphone permission. Returns true if granted.
  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  /// Start recording. Throws if permission denied or already recording.
  Future<void> startRecording() async {
    if (_isRecording) return;

    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) throw Exception('Microphone permission denied');

    String path;
    if (kIsWeb) {
      path = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
    } else {
      final dir = await getTemporaryDirectory();
      // Plain filesystem path — no file:// prefix. The record package
      // writes here and we pass this same path to uploadVoiceNote.
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _isRecording = true;
    _recordingStarted = DateTime.now();
    _currentRecordingPath = path;
  }

  /// Stop recording and return the duration in seconds. Returns null if not recording.
  Future<({String path, int duration})?> stopRecording() async {
    if (!_isRecording) return null;

    // Capture the known path BEFORE calling stop() — on iOS the record package
    // sometimes returns null or a mismatched path from stop(), so we fall back
    // to the path we stored at startRecording() time.
    final knownPath = _currentRecordingPath;

    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (_) {
      stoppedPath = null;
    }
    _isRecording = false;

    final duration = _recordingStarted != null
        ? DateTime.now().difference(_recordingStarted!).inSeconds
        : 0;
    _recordingStarted = null;

    // Use the path returned by stop(); if null, fall back to the known start path.
    final resolvedPath = stoppedPath ?? knownPath;
    if (resolvedPath == null) return null;

    // Strip file:// scheme so File() works on iOS
    final cleanPath = resolvedPath.startsWith('file://')
        ? Uri.parse(resolvedPath).toFilePath()
        : resolvedPath;

    // Give the OS up to 500 ms to flush the file
    if (!kIsWeb) {
      for (var i = 0; i < 5; i++) {
        if (await File(cleanPath).exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    _currentRecordingPath = null;
    return (path: cleanPath, duration: duration);
  }

  /// Cancel recording and discard the audio.
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.cancel();
    _isRecording = false;
    _recordingStarted = null;

    // Delete temp file
    if (_currentRecordingPath != null && !kIsWeb) {
      try {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _currentRecordingPath = null;
  }

  /// Current recording duration (live).
  Duration get recordingDuration {
    if (_recordingStarted == null) return Duration.zero;
    return DateTime.now().difference(_recordingStarted!);
  }

  // ── Upload API ────────────────────────────────────────────────────────────

  /// Upload the recorded voice file to Firebase Storage.
  /// Returns the public download URL.
  Future<String> uploadVoiceNote(String localPath, {String? conversationId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = kIsWeb ? 'webm' : 'm4a';
    final folder = conversationId != null ? 'voice_notes/$conversationId' : 'voice_notes/$uid';
    final storagePath = '$folder/${uid}_$timestamp.$ext';

    final ref = FirebaseStorage.instance.ref(storagePath);

    UploadTask task;
    if (kIsWeb) {
      // On web, `record` writes to a blob URL – we can't read file bytes easily here.
      // In practice the web path returned by record is a blob URI; skip upload and
      // return it directly (the blob is local). For full web support use
      // record's `stream` mode in a future iteration.
      return localPath;
    } else {
      // stopRecording() already strips file:// — handle both just in case.
      final cleanPath = localPath.startsWith('file://')
          ? Uri.parse(localPath).toFilePath()
          : localPath;
      final file = File(cleanPath);
      if (!await file.exists()) {
        throw Exception('Voice recording not found at path: $cleanPath');
      }
      task = ref.putFile(
        file,
        SettableMetadata(contentType: 'audio/mp4'),
      );
    }

    final snapshot = await task;
    final url = await snapshot.ref.getDownloadURL();

    // Clean up temp file
    if (!kIsWeb) {
      try {
        final cleanPath = localPath.startsWith('file://')
            ? Uri.parse(localPath).toFilePath()
            : localPath;
        final f = File(cleanPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    return url;
  }

  // ── Playback API ──────────────────────────────────────────────────────────

  /// Play a voice note from [url]. If the same URL is already playing, pause it.
  Future<void> togglePlayback(String url) async {
    if (_playingUrl == url && _isPlaying) {
      await _player.pause();
      _isPlaying = false;
      _playingUrlController.add(url); // notify listeners (still "active" but paused)
      return;
    }

    if (_playingUrl == url && !_isPlaying) {
      await _player.resume();
      _isPlaying = true;
      _playingUrlController.add(url);
      return;
    }

    // Different URL – stop current and play new
    await _player.stop();
    _playingUrl = url;
    _isPlaying = false;
    _playingUrlController.add(url);

    await _player.play(UrlSource(url));
    _isPlaying = true;
    _playingUrlController.add(url);
  }

  /// Stop any current playback.
  Future<void> stopPlayback() async {
    await _player.stop();
    _playingUrl = null;
    _isPlaying = false;
    _playingUrlController.add(null);
  }

  /// Get total duration of an audio file (for display before playback).
  Future<Duration?> getDuration(String url) async {
    try {
      final completer = Completer<Duration?>();
      final tempPlayer = AudioPlayer();
      tempPlayer.onDurationChanged.listen((d) {
        if (!completer.isCompleted) completer.complete(d);
      });
      await tempPlayer.setSourceUrl(url);
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      await tempPlayer.dispose();
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Format seconds into mm:ss string.
  static String formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String formatDurationObj(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '00')}';
  }
}
