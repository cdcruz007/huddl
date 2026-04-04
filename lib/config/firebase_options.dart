import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for the Huddl Connect project.
///
/// Generated from:
///   - google-services.json  (Android)
///   - Firebase Console       (Web)
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Web ─────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBk2hsDAYRFj1eLM8XZD5aQndLJBiXTZp4',
    appId: '1:879152141283:web:ebc332c010425e8a9186d6',
    messagingSenderId: '879152141283',
    projectId: 'huddl-connect',
    authDomain: 'huddl-connect.firebaseapp.com',
    storageBucket: 'huddl-connect.firebasestorage.app',
  );

  // ── Android ─────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBPWoXNhqNY-HZLG8cBmE8voZ75TRKBTOw',
    appId: '1:879152141283:android:e33a13e587e540519186d6',
    messagingSenderId: '879152141283',
    projectId: 'huddl-connect',
    storageBucket: 'huddl-connect.firebasestorage.app',
  );

  // ── iOS (placeholder — register iOS app in Firebase Console when ready) ─
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBPWoXNhqNY-HZLG8cBmE8voZ75TRKBTOw',
    appId: '1:879152141283:android:e33a13e587e540519186d6', // Replace with iOS appId
    messagingSenderId: '879152141283',
    projectId: 'huddl-connect',
    storageBucket: 'huddl-connect.firebasestorage.app',
    iosBundleId: 'com.huddlconnect.huddlConnect', // Replace with real bundle ID
  );
}
