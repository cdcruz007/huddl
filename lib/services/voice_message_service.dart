import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'web_blob_helper_stub.dart' if (dart.library.html) 'web_blob_helper.dart';

/// S-04: Distinguishes DM vs group voice-note upload paths.
/// DM  → voice_notes/dm/{conversationId}/{uid}_{ts}.{ext}
/// Group → voice_notes/group/{groupId}/{uid}_{ts}.{ext}
/// The uid-fallback ('voice_notes/{uid}/...') is eliminated: callers must
/// always resolve contextId before uploading.
enum VoiceNotePathType { dm, group }

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
        if (kDebugMode) {
          if (kDebugMode) debugPrint('[VoiceMessageService] audio context error: $e');
        }
      }
    }

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      // Emit the current URL so bubble widgets update their icon immediately
      _playingUrlController.add(_isPlaying ? _playingUrl : null);
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        // Reset position to zero and notify listeners so bubble resets
        _positionController.add(Duration.zero);
        _playingUrl = null;
        _playingUrlController.add(null);
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
  ///
  /// Upload strategy (mobile):
  ///   1. Read the recording file into memory as bytes.
  ///   2. Upload with [putData] — this is the most reliable path on both iOS
  ///      and Android with the new `.firebasestorage.app` bucket domain.
  ///
  /// Why not [putFile]?
  ///   On iOS, [putFile] delegates to FIRStorageUploadTask which on some iOS
  ///   versions tries to verify the storage bucket hostname directly, producing
  ///   the error "firebase_storage/unknown – A server with the specified
  ///   hostname could not be found" (NSURLErrorCannotFindHost / -1003).
  ///   [putData] sends bytes as NSData via a different URLSession code path
  ///   that correctly targets firebasestorage.googleapis.com and avoids the
  ///   DNS lookup failure.  It is also more resilient on Android under poor
  ///   network conditions.  The memory overhead is acceptable for voice notes
  ///   (≤ 25 MB per the storage rules).
  /// Upload a recorded voice note to Firebase Storage.
  ///
  /// [pathType] — VoiceNotePathType.dm  → voice_notes/dm/{contextId}/...
  ///              VoiceNotePathType.group → voice_notes/group/{contextId}/...
  /// [contextId] — conversationId (DM) or groupId (group). Must be non-null;
  ///               callers are required to resolve this before calling.
  ///               The uid-fallback path has been eliminated (S-04).
  Future<String> uploadVoiceNote(
    String localPath, {
    required VoiceNotePathType pathType,
    required String contextId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = kIsWeb ? 'webm' : 'm4a';
    final typeSegment = pathType == VoiceNotePathType.dm ? 'dm' : 'group';
    final storagePath = 'voice_notes/$typeSegment/$contextId/${uid}_$timestamp.$ext';

    final ref = FirebaseStorage.instance.ref(storagePath);

    UploadTask task;
    if (kIsWeb) {
      // On web, `record` returns a blob: URL.  We fetch the blob as bytes using
      // XHR then upload via putData so the audio is stored in Firebase Storage
      // and playable by all users (a blob: URL is local to one browser tab).
      final bytes = await fetchBlobAsBytes(localPath);
      task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'audio/webm'),
      );
    } else {
      // Mobile (iOS & Android): read bytes first, then upload with putData.
      // stopRecording() already strips file:// — handle both just in case.
      final cleanPath = localPath.startsWith('file://')
          ? Uri.parse(localPath).toFilePath()
          : localPath;
      final file = File(cleanPath);
      if (!await file.exists()) {
        throw Exception('Voice recording not found at path: $cleanPath');
      }
      // Read into memory — avoids the iOS putFile hostname-resolution bug.
      final bytes = await file.readAsBytes();
      task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'audio/mp4'),
      );
    }

    final snapshot = await task;
    final url = await snapshot.ref.getDownloadURL();

    // Clean up temp file after successful upload
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
  ///
  /// Android note: audioplayers 6.x defaults to LOW_LATENCY mode which does
  /// not support HTTP streaming. We must set PlayerMode.mediaPlayer first so
  /// Android MediaPlayer is used instead of SoundPool.
  ///
  /// Firebase Storage tokens can expire, so we refresh the URL immediately
  /// before playback using [_refreshStorageUrl].
  Future<void> togglePlayback(String url) async {
    try {
      // ── Fix 1: Refresh Firebase Storage URL before playback ──────────────
      // Tokens embedded in download URLs can expire. Refreshing here ensures
      // we always play with a valid, non-expired signed URL.
      final freshUrl = await _refreshStorageUrl(url);

      if (_playingUrl == url && _isPlaying) {
        await _player.pause();
        _isPlaying = false;
        _playingUrlController.add(url);
        return;
      }

      if (_playingUrl == url && !_isPlaying) {
        await _player.resume();
        _isPlaying = true;
        _playingUrlController.add(url);
        return;
      }

      // Different URL — stop current and play new
      await _player.stop();
      _playingUrl = url;
      _isPlaying = false;
      _playingUrlController.add(url);

      if (!kIsWeb) {
        // ── Fix 2: Android PlayerMode ordering ──────────────────────────────
        // setPlayerMode MUST come first on Android. Calling play(UrlSource())
        // in one step skips explicit source-set ordering and causes a
        // platform exception on some Android versions after stop().
        // We set the mode, configure the AVAudioSession (iOS), set the source,
        // then call resume() — this is the correct sequence for both platforms.
        await _player.setPlayerMode(PlayerMode.mediaPlayer);

        // ── Fix 3: iOS AVAudioSession — surface errors instead of swallowing ─
        // The session can be deactivated by interruptions (phone calls, Siri,
        // other audio apps). Previously the catch(_) silently swallowed the
        // failure, causing play() to throw a cryptic platform exception.
        // Now we log and rethrow so the real cause reaches the UI.
        try {
          await _player.setAudioContext(
            AudioContext(
              iOS: AudioContextIOS(
                category: AVAudioSessionCategory.playback,
                options: const {},
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
          if (kDebugMode) {
            if (kDebugMode) {
              debugPrint('[VoiceMessageService] AVAudioSession error: $e');
            }
          }
          rethrow; // surface it — silent swallow causes cryptic play() failure
        }

        // Set source URL explicitly then resume — avoids the Android race
        // where combined play(UrlSource()) doesn't guarantee mode is applied
        // before the source is prepared by the platform MediaPlayer.
        await _player.setSourceUrl(freshUrl);
        await _player.resume();
      } else {
        // Web: setSourceUrl + resume() is not needed; play(UrlSource()) works fine.
        await _player.play(UrlSource(freshUrl));
      }

      _isPlaying = true;
      _playingUrlController.add(url);
    } catch (e) {
      // Reset state so the bubble doesn't get stuck on a broken play icon
      _isPlaying = false;
      _playingUrl = null;
      _playingUrlController.add(null);
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[VoiceMessageService] playback error for $url: $e');
      }
      // Re-throw so the UI can show a snackbar
      rethrow;
    }
  }

  /// Stop any current playback.
  Future<void> stopPlayback() async {
    await _player.stop();
    _playingUrl = null;
    _isPlaying = false;
    _playingUrlController.add(null);
  }

  /// Seek to [position] in the currently playing audio.
  Future<void> seekTo(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) debugPrint('[VoiceMessageService] seek error: $e');
      }
    }
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

  /// Refresh a Firebase Storage download URL to prevent token-expiry failures.
  ///
  /// Firebase Storage signed tokens in download URLs can expire (typically
  /// after a few hours to a few days). Calling [getDownloadURL()] via
  /// [refFromURL()] fetches a fresh token from the Firebase Storage backend.
  ///
  /// Falls back to the original [url] if:
  ///  - the URL is not a Firebase Storage URL (non-Firebase audio source)
  ///  - the refresh call fails for any reason (network error, bad ref, etc.)
  Future<String> _refreshStorageUrl(String url) async {
    if (!url.contains('firebasestorage.googleapis.com')) return url;
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      return await ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) {
        if (kDebugMode) {
          debugPrint('[VoiceMessageService] URL refresh failed, using original: $e');
        }
      }
      return url; // fall back to the original — playback may still succeed
    }
  }

  /// Format seconds into mm:ss string.
  static String formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String formatDurationObj(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
