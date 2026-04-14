import Flutter
import UIKit
import Foundation

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

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
