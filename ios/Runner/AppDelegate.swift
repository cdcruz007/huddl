import Flutter
import UIKit
import Foundation
import UserNotifications

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
// APNs REGISTRATION FIX:
//
//  Firebase phone auth calls assertionFailure() internally on iOS if APNs
//  is not registered at the moment verifyPhoneNumber() is called. This
//  causes a native SIGTRAP crash that Dart cannot catch.
//
//  Fix: request notification authorisation immediately at launch so that
//  APNs has time to hand a device token to Firebase before the user reaches
//  the verification screen (typically ~3 seconds into the session).
//
// ═══════════════════════════════════════════════════════════════════════════

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ── Register Flutter plugins (must be first) ─────────────────────
        GeneratedPluginRegistrant.register(with: self)

        // ── Request APNs registration IMMEDIATELY ────────────────────────
        // This ensures Firebase receives an APNs device token before the
        // user reaches the phone verification screen, preventing the
        // internal assertionFailure crash inside PhoneAuthProvider.
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error = error {
                    print("Huddl: APNs authorisation error: \(error.localizedDescription)")
                }
                // Register with APNs regardless of user permission choice.
                // Firebase needs the device token even for silent push.
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
    // automatically (via swizzling). We override only to log it.
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Super call passes the token to Firebase Auth (via method swizzling).
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
        print("Huddl: APNs device token registered — Firebase phone auth is ready.")
    }

    override func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Even if the device can't register (e.g. simulator), pass through.
        super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
        // Firebase will fall back to reCAPTCHA flow — that's fine.
        print("Huddl: APNs registration failed (\(error.localizedDescription)) — Firebase will use reCAPTCHA fallback.")
    }
}
