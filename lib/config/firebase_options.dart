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
  // Values sourced from GoogleService-Info.plist (ios/Runner/GoogleService-Info.plist)
  // Project: huddl-connect  |  Bundle ID: com.huddlconnect.huddlConnect
  //
  // NOTE: CLIENT_ID / iosClientId is absent from this plist because no
  // OAuth 2.0 client has been created for this iOS app yet.  If you need
  // Google Sign-In, go to Firebase Console → Authentication → Sign-in method
  // → Google → enable it, then re-download the plist to get CLIENT_ID.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBJfw203W_lXYri_TPA6XL4nrn03D1IfGI',
    appId: '1:879152141283:ios:bdac2f6012c53a8d9186d6',
    messagingSenderId: '879152141283',
    projectId: 'huddl-connect',
    storageBucket: 'huddl-connect.firebasestorage.app',
    iosBundleId: 'com.huddlconnect.huddlConnect',
  );
}
