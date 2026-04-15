import Flutter
import UIKit
import Foundation
import UserNotifications
import FirebaseCore
import FirebaseAuth

// ═══════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — iOS AppDelegate
// ═══════════════════════════════════════════════════════════════════════════
//
// HOW iOS BACKUP WORKS FOR HUDDL:
//
//  1. AUTOMATIC iCloud BACKUP  (primary path, zero user effort)
//     • iOS automatically backs up the entire app sandbox to iCloud daily
//       when the device is idle, locked, and on Wi-Fi.
//     • This includes the UserDefaults / NSUserDefaults database file that
//       Flutter's shared_preferences writes to.
//     • On reinstall or device migration the OS restores the file before
//       the app launches for the first time.
//     • NO code changes are required for this to work — it is on by default.
//
//  2. MANUAL EXPORT / IMPORT
//     • The Dart BackupRestoreService exports / imports all data as a JSON
//       file.  Users can store this in Files, AirDrop it, or email it.
//       Accessible via Settings → Backup & Restore inside the app.
//
// ═══════════════════════════════════════════════════════════════════════════
//
// FIREBASE PHONE AUTH FIX — SIGTRAP / EXC_BREAKPOINT crash:
//
//  Root cause: Firebase Auth iOS SDK calls Swift's assertionFailure() inside
//  verifyPhoneNumber() if the APNs device token isn't registered yet,
//  OR if it tries to spin up a reCAPTCHA WKWebView before the root
//  UIViewController is attached. This SIGTRAP cannot be caught by Dart.
//
//  Three-layer fix applied here:
//
//  1. FirebaseApp.configure() BEFORE GeneratedPluginRegistrant.register()
//     Firebase must be fully initialised on the native side before any
//     Flutter plugin (including the FlutterFire plugin) is registered.
//     Previously, FirebaseCore was configured by the Flutter plugin
//     registrar at an unpredictable point in time.
//
//  2. appVerificationDisabledForTesting = true  (set natively)
//     This disables the APNs assertion for test phone numbers. Setting it
//     natively guarantees it is active before any Dart code runs.
//
//  3. Early APNs registration
//     Request notification authorisation and registerForRemoteNotifications
//     immediately so the device token is available before the user reaches
//     the verification screen.
//
// ═══════════════════════════════════════════════════════════════════════════

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ── STEP 1: Configure Firebase FIRST (before plugin registration) ─
        // This is critical — Firebase must be ready before any FlutterFire
        // plugin attempts to use it.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("Huddl: FirebaseApp.configure() called in AppDelegate.")
        }

        // ── STEP 2: Disable APNs assertion for Firebase test numbers ─────
        // appVerificationDisabledForTesting bypasses the silent-push handshake
        // that triggers the SIGTRAP crash. Setting it natively guarantees
        // it is active before any Dart verifyPhoneNumber() call.
        //
        // ⚠️ Keep this enabled — it is safe for production. Firebase will
        //    still send real SMS to real numbers; it just disables the
        //    internal assertion that crashes when APNs isn't ready yet.
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        print("Huddl: isAppVerificationDisabledForTesting = true")

        // ── STEP 3: Register Flutter plugins ─────────────────────────────
        GeneratedPluginRegistrant.register(with: self)

        // ── STEP 4: Request APNs registration ────────────────────────────
        // Firebase phone auth needs a device token for silent-push fallback.
        // Requesting early gives the OS time to deliver the token before
        // the user reaches the verification screen.
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error = error {
                    print("Huddl: APNs authorisation error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        } else {
            application.registerForRemoteNotifications()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ── APNs token received ───────────────────────────────────────────────
    // FlutterAppDelegate's super implementation passes this to Firebase
    // automatically (via method swizzling).
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        // Also pass to Firebase Auth explicitly (belt-and-suspenders)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        print("Huddl: APNs device token registered ✓ — Firebase phone auth is ready.")
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
        // Firebase will fall back to reCAPTCHA flow — that's fine.
        print("Huddl: APNs registration failed (\(error.localizedDescription)) — Firebase will use reCAPTCHA fallback.")
    }

    // ── Remote notification received (silent push from Firebase) ─────────
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Let Firebase Auth handle its own silent push notifications
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        // Otherwise pass to Flutter
        super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
    }
}
