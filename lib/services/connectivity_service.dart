// NO-OFFLINE-INDICATOR-1: connectivity detection singleton.
//
// Uses connectivity_plus 7.1.1 (List<ConnectivityResult> API).
// IMPORTANT: detects NETWORK INTERFACE presence (wifi/mobile/ethernet),
// NOT true internet reachability. A "connected but no internet" state reads
// as online — standard platform limitation; acceptable for a UI hint banner.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._() { _init(); }
  static final ConnectivityService _instance = ConnectivityService._();
  factory ConnectivityService() => _instance;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  void _init() {
    // connectivity_plus 6.x+ returns List<ConnectivityResult> on both
    // .onConnectivityChanged stream and .checkConnectivity().
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        notifyListeners();
      }
    });

    // Initial state check — don't wait for the stream's first event.
    Connectivity().checkConnectivity().then((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _isOnline) {
        _isOnline = online;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
