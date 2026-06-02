// =============================================================================
// mock_channels.dart — Deterministic platform-channel mocks for Huddl E2E tests
//
// Registers MethodChannel / EventChannel interceptors for every native plugin
// used across workflows A–H.  Call [MockChannels.setUp()] at the top of each
// test and [MockChannels.tearDown()] in addTearDown().
//
// Channels mocked:
//  • geolocator            — GPS position, permission state
//  • url_launcher          — captures URIs instead of opening the dialer/browser
//  • permission_handler    — grant / deny per-PermissionGroup
//  • image_picker          — supplies a fixture PNG bytes response
//  • file_picker           — supplies a fixture audio bytes response
//  • record (audio)        — start/stop recording → fixture path
//  • audioplayers          — player state machine, position stream
//
// Usage:
//   setUp(() async { await MockChannels.setUp(); });
//   addTearDown(() async { await MockChannels.tearDown(); });
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture GPS coordinate — Hackney, London (for borough-scope tests)
const double kMockLat = 51.5450;
const double kMockLng = -0.0553;
const String kMockBorough = 'Hackney';

/// Fixture file: 1×1 transparent PNG (44 bytes) used as image_picker response
final Uint8List kFixturePngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG sig
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
  0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
  0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Fixture path that "record" service writes to (resolved in /tmp for tests)
const String kMockVoiceNotePath = '/tmp/huddl_test_voice_note.m4a';

/// URI captured by the last url_launcher call
String? lastLaunchedUri;

/// Tracks which permissions are currently "granted" for override in tests
final Map<int, int> _permissionStatus = {};

// ---------------------------------------------------------------------------
// PermissionStatus values (permission_handler plugin encoding):
//   0 = denied, 1 = granted, 2 = restricted, 3 = limited, 4 = permanentlyDenied
// ---------------------------------------------------------------------------
const int _pGranted          = 1;
const int _pDenied           = 0;
const int _pPermanentlyDenied = 4;

// Permission group indices matching permission_handler 11.x
// (these are stable — sourced from PermissionGroup enum ordinals)
const int _permMicrophone    = 9;
const int _permNotification  = 14;
const int _permLocation      = 4;
const int _permCamera        = 3;
const int _permStorage       = 16;
const int _permPhotos        = 20;

class MockChannels {
  MockChannels._();

  // Channels
  static const _geolocator         = MethodChannel('flutter.baseflow.com/geolocator');
  static const _urlLauncher        = MethodChannel('plugins.flutter.io/url_launcher');
  static const _urlLauncherWebview = MethodChannel('plugins.flutter.io/url_launcher_android');
  static const _permHandler        = MethodChannel('flutter.baseflow.com/permissions/methods');
  static const _imagePicker        = MethodChannel('plugins.flutter.io/image_picker');
  static const _filePicker         = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  static const _record             = MethodChannel('com.llfbandit.record/messages');
  static const _audioPlayers       = MethodChannel('xyz.luan/audioplayers');
  static const _audioPlayersGlobal = MethodChannel('xyz.luan/audioplayers.global');

  /// Resets captured state
  static void _resetState() {
    lastLaunchedUri = null;
    _permissionStatus
      ..clear()
      ..[_permMicrophone]    = _pGranted
      ..[_permNotification]  = _pGranted
      ..[_permLocation]      = _pGranted
      ..[_permCamera]        = _pGranted
      ..[_permStorage]       = _pGranted
      ..[_permPhotos]        = _pGranted;
  }

  /// Grant specific permission (call before the test exercises it)
  static void grantPermission(int permGroup) {
    _permissionStatus[permGroup] = _pGranted;
  }

  /// Deny specific permission
  static void denyPermission(int permGroup) {
    _permissionStatus[permGroup] = _pDenied;
  }

  /// Permanently deny specific permission
  static void permanentlyDenyPermission(int permGroup) {
    _permissionStatus[permGroup] = _pPermanentlyDenied;
  }

  // Convenience aliases for test readability
  static void grantMicrophone()    => grantPermission(_permMicrophone);
  static void denyMicrophone()     => denyPermission(_permMicrophone);
  static void grantLocation()      => grantPermission(_permLocation);
  static void denyLocation()       => denyPermission(_permLocation);
  static void permanentlyDenyLocation() => permanentlyDenyPermission(_permLocation);
  static void grantNotification()  => grantPermission(_permNotification);
  static void denyNotification()   => denyPermission(_permNotification);
  static void grantCamera()        => grantPermission(_permCamera);
  static void denyCamera()         => denyPermission(_permCamera);

  static Future<void> setUp() async {
    _resetState();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_geolocator, _geolocatorHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncher, _urlLauncherHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherWebview, _urlLauncherHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permHandler, _permissionHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePicker, _imagePickerHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_filePicker, _filePickerHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_record, _recordHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayers, _audioPlayersHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayersGlobal, _audioPlayersGlobalHandler);
  }

  static Future<void> tearDown() async {
    for (final ch in [
      _geolocator, _urlLauncher, _urlLauncherWebview,
      _permHandler, _imagePicker, _filePicker,
      _record, _audioPlayers, _audioPlayersGlobal,
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null);
    }
    _resetState();
  }

  // ---------------------------------------------------------------------------
  // GEOLOCATOR HANDLER
  // ---------------------------------------------------------------------------
  static Future<dynamic> _geolocatorHandler(MethodCall call) async {
    switch (call.method) {
      case 'checkPermission':
      case 'requestPermission':
        // 2 = LocationPermission.whileInUse (granted)
        return (_permissionStatus[_permLocation] == _pGranted) ? 2 : 0;

      case 'isLocationServiceEnabled':
        return _permissionStatus[_permLocation] != _pPermanentlyDenied;

      case 'getCurrentPosition':
      case 'getLastKnownPosition':
        if (_permissionStatus[_permLocation] != _pGranted) {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Location permission denied',
          );
        }
        return {
          'latitude':  kMockLat,
          'longitude': kMockLng,
          'accuracy':  15.0,
          'altitude':  0.0,
          'speed':     0.0,
          'speedAccuracy': 0.0,
          'heading':   0.0,
          'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
          'isMocked':  true,
        };

      case 'getPositionStream':
        return null; // stream setup — handled by EventChannel stub

      case 'openAppSettings':
      case 'openLocationSettings':
        return true;

      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // URL LAUNCHER HANDLER  — captures URI instead of opening system browser/dialer
  // ---------------------------------------------------------------------------
  static Future<dynamic> _urlLauncherHandler(MethodCall call) async {
    switch (call.method) {
      case 'canLaunch':
        return true;
      case 'launch':
      case 'launchUrl':
        final url = call.arguments is Map
            ? (call.arguments as Map)['url'] as String?
            : call.arguments as String?;
        lastLaunchedUri = url;
        return true;
      case 'closeWebView':
        return null;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PERMISSION HANDLER
  // ---------------------------------------------------------------------------
  static Future<dynamic> _permissionHandler(MethodCall call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        final perm = call.arguments as int;
        return _permissionStatus[perm] ?? _pGranted;

      case 'requestPermissions':
        final perms = (call.arguments as List).cast<int>();
        final result = <int, int>{};
        for (final p in perms) {
          result[p] = _permissionStatus[p] ?? _pGranted;
        }
        return result;

      case 'shouldShowRequestPermissionRationale':
        final perm = call.arguments as int;
        return _permissionStatus[perm] == _pDenied;

      case 'openAppSettings':
        return true;

      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // IMAGE PICKER
  // ---------------------------------------------------------------------------
  static Future<dynamic> _imagePickerHandler(MethodCall call) async {
    switch (call.method) {
      case 'pickImage':
      case 'pickImages':
      case 'pickMedia':
        // Return a fixture file-path map (image_picker 1.x format)
        return {
          'path': '/tmp/huddl_test_fixture.png',
          'name': 'fixture.png',
          'mimeType': 'image/png',
          'bytes': kFixturePngBytes,
        };
      case 'pickMultiImage':
        return [
          {
            'path': '/tmp/huddl_test_fixture.png',
            'name': 'fixture.png',
            'mimeType': 'image/png',
          }
        ];
      case 'retrieveLostData':
        return null;
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // FILE PICKER
  // ---------------------------------------------------------------------------
  static Future<dynamic> _filePickerHandler(MethodCall call) async {
    if (call.method == 'pickFiles') {
      return {
        'files': [
          {
            'name': 'fixture_voice.m4a',
            'path': kMockVoiceNotePath,
            'size': 4096,
            'extension': 'm4a',
          }
        ]
      };
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // RECORD (audio recording)  — com.llfbandit.record
  // ---------------------------------------------------------------------------
  static bool _isRecording = false;

  static Future<dynamic> _recordHandler(MethodCall call) async {
    switch (call.method) {
      case 'create':
      case 'dispose':
        return null;

      case 'hasPermission':
      case 'isEncoderSupported':
        return _permissionStatus[_permMicrophone] == _pGranted;

      case 'start':
        if (_permissionStatus[_permMicrophone] != _pGranted) {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Microphone permission denied',
          );
        }
        _isRecording = true;
        return null;

      case 'stop':
        _isRecording = false;
        // Return fixture path with non-zero size so duration > 0
        return kMockVoiceNotePath;

      case 'pause':
      case 'resume':
        return null;

      case 'isPaused':
        return false;

      case 'isRecording':
        return _isRecording;

      case 'getAmplitude':
        return {'current': -20.0, 'max': -15.0};

      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // AUDIOPLAYERS — xyz.luan/audioplayers
  // ---------------------------------------------------------------------------
  static const int _stateIdle    = 0;
  static const int _statePlaying = 1;
  static const int _statePaused  = 2;
  static const int _stateStopped = 3;

  static int _playerState = _stateIdle;
  static int _positionMs  = 0;
  static final int _durationMs = 5000; // 5 s fixture

  static Future<dynamic> _audioPlayersHandler(MethodCall call) async {
    switch (call.method) {
      case 'setSourceUrl':
      case 'setSourceDeviceFile':
      case 'setSourceBytes':
        _playerState = _stateIdle;
        _positionMs  = 0;
        return null;

      case 'resume':
      case 'play':
        _playerState = _statePlaying;
        _positionMs  = 250; // simulate position advance
        return null;

      case 'pause':
        _playerState = _statePaused;
        return null;

      case 'stop':
        _playerState = _stateStopped;
        _positionMs  = 0;
        return null;

      case 'release':
        _playerState = _stateIdle;
        return null;

      case 'getPosition':
        return _positionMs;

      case 'getDuration':
        return _durationMs;

      case 'getPlayerState':
        return _playerState;

      case 'setVolume':
      case 'setBalance':
      case 'setPlaybackRate':
      case 'setReleaseMode':
      case 'seek':
        return null;

      default:
        return null;
    }
  }

  static Future<dynamic> _audioPlayersGlobalHandler(MethodCall call) async {
    // global channel: audio focus, log level — just ack
    return null;
  }

  // ---------------------------------------------------------------------------
  // Convenience: simulate player has advanced (for scrubber assertion)
  // ---------------------------------------------------------------------------
  static bool get isPlayerPlaying => _playerState == _statePlaying;
  static int   get playerPositionMs => _positionMs;
  static int   get playerDurationMs => _durationMs;

  // Expose permission constants for test assertions
  static int get permMicrophone   => _permMicrophone;
  static int get permLocation     => _permLocation;
  static int get permNotification => _permNotification;
  static int get permCamera       => _permCamera;
}
