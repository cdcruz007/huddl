import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for the Huddl Connect project.
///
/// Generated from:
///   - google-services.json  (Android)
///   - Firebase Console       (Web)
///
/// NOTE: Firebase API keys are designed to be included in client code.
/// Security is enforced via Firebase Security Rules and domain/app restrictions
/// configured in the Firebase Console, not by keeping these keys secret.
/// See: https://firebase.google.com/docs/projects/api-keys
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

  // ── iOS ─────────────────────────────────────────────────────────────────
  //
  // ╔══════════════════════════════════════════════════════════════════════╗
  // ║  TODO — REPLACE VALUES BEFORE BUILDING FOR iOS / TESTFLIGHT         ║
  // ╠══════════════════════════════════════════════════════════════════════╣
  // ║  After downloading GoogleService-Info.plist from Firebase Console,  ║
  // ║  copy these values from that file into the fields below:            ║
  // ║                                                                      ║
  // ║  Field in firebase_options.dart  ← Key in GoogleService-Info.plist  ║
  // ║  ─────────────────────────────────────────────────────────────────  ║
  // ║  apiKey              ← API_KEY                                       ║
  // ║  appId               ← GOOGLE_APP_ID                                 ║
  // ║  messagingSenderId   ← GCM_SENDER_ID                                 ║
  // ║  iosBundleId         ← BUNDLE_ID  (= com.huddlconnect.huddlConnect)  ║
  // ║  iosClientId         ← CLIENT_ID                                     ║
  // ║                                                                      ║
  // ║  projectId and storageBucket are the same as Android — no change.   ║
  // ║                                                                      ║
  // ║  HOW TO GET GoogleService-Info.plist:                                ║
  // ║    1. https://console.firebase.google.com → huddl-connect project   ║
  // ║    2. ⚙️ Project settings → Your apps → Add app → iOS               ║
  // ║    3. Bundle ID: com.huddlconnect.huddlConnect                       ║
  // ║    4. Download GoogleService-Info.plist                              ║
  // ║    5. Place file at:  ios/Runner/GoogleService-Info.plist            ║
  // ║    6. Update the values below                                        ║
  // ╚══════════════════════════════════════════════════════════════════════╝
  static const FirebaseOptions ios = FirebaseOptions(
    // TODO: replace with API_KEY from GoogleService-Info.plist
    apiKey: 'REPLACE_WITH_IOS_API_KEY',
    // TODO: replace with GOOGLE_APP_ID from GoogleService-Info.plist
    // Format: 1:879152141283:ios:xxxxxxxxxxxx
    appId: 'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '879152141283',
    projectId: 'huddl-connect',
    storageBucket: 'huddl-connect.firebasestorage.app',
    // TODO: replace with CLIENT_ID from GoogleService-Info.plist
    iosClientId: 'REPLACE_WITH_IOS_CLIENT_ID',
    iosBundleId: 'com.huddlconnect.huddlConnect',
  );
}
