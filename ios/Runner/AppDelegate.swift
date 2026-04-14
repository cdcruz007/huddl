import Flutter
import UIKit
import Foundation

// ═══════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — iOS AppDelegate with iCloud KV Backup Support
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
//  2. NSUbiquitousKeyValueStore SYNC  (this file — secondary/instant path)
//     • On every app foregrounding and on applicationSignificantTimeChange
//       we copy all SharedPreferences keys to iCloud KV store.
//     • On first launch, if local storage is empty but iCloud KV has data,
//       we restore from iCloud KV immediately (useful when standard backup
//       hasn't caught up yet, e.g. right after install on a new phone).
//     • Keys longer than 1 MB or the total payload > 1 MB are skipped and
//       logged; these edge cases are handled by the standard iCloud backup.
//
//  3. MANUAL EXPORT / IMPORT
//     • The Dart BackupRestoreService exports / imports all data as a JSON
//       file.  Users can store this in Files, AirDrop it, or email it.
//       Accessible via Settings → Backup & Restore inside the app.
//
// ═══════════════════════════════════════════════════════════════════════════

@main
@objc class AppDelegate: FlutterAppDelegate {

    // The shared_preferences plugin stores all values under this suite name
    // (the app's bundle identifier).
    private static let userDefaultsSuiteName: String = {
        return Bundle.main.bundleIdentifier ?? "com.huddlconnect.connect"
    }()

    // NSUbiquitousKeyValueStore max sizes (Apple limits)
    private static let maxValueBytes  = 1_024 * 1_024      // 1 MB per key
    private static let maxTotalBytes  = 1_024 * 1_024      // 1 MB total KV store

    // Keys that are transient / device-specific and should NOT be synced
    private static let excludedKeys: Set<String> = [
        "flutter.ai_discovery_last_run",
        "flutter.last_login_timestamp",
        "flutter.data_reset_v2",
        "flutter.FlutterSharedPreferences",
    ]

    // ── Application lifecycle ────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Listen for iCloud KV change notifications (another device updated data)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudKVStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )

        // Kick off initial KV store sync
        NSUbiquitousKeyValueStore.default.synchronize()

        // If local SharedPreferences are empty but iCloud KV has data,
        // restore from iCloud KV immediately (handles brand-new installs).
        restoreFromICloudKVIfNeeded()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationWillEnterForeground(_ application: UIApplication) {
        // Refresh from iCloud whenever the app comes to the foreground
        NSUbiquitousKeyValueStore.default.synchronize()
        syncLocalToICloudKV()
    }

    override func applicationSignificantTimeChange(_ application: UIApplication) {
        // Also sync at significant time events (e.g. midnight, timezone change)
        syncLocalToICloudKV()
    }

    // ── iCloud KV change handler ─────────────────────────────────────────

    @objc private func iCloudKVStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        else { return }

        // Use raw integer values for compatibility across all iOS versions:
        // NSUbiquitousKeyValueStoreServerChange       = 0
        // NSUbiquitousKeyValueStoreInitialSyncChange  = 1
        // NSUbiquitousKeyValueStoreQuotaViolationChange = 2
        // NSUbiquitousKeyValueStoreAccountChange      = 3
        switch reasonRaw {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Another device (or first-sync) updated values — pull them down
            pullICloudKVToLocal()
        case NSUbiquitousKeyValueStoreAccountChange:
            // User changed iCloud account — full resync
            syncLocalToICloudKV()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            // We exceeded the 1 MB quota — nothing we can do at runtime;
            // manual backup is still available.
            print("HuddlBackup: iCloud KV quota exceeded. Use manual backup.")
        default:
            break
        }
    }

    // ── Sync helpers ─────────────────────────────────────────────────────

    /// Copy all local SharedPreferences keys to NSUbiquitousKeyValueStore.
    private func syncLocalToICloudKV() {
        let defaults = UserDefaults.standard
        let kvStore  = NSUbiquitousKeyValueStore.default

        var totalBytes = 0
        var syncedCount = 0
        var skippedCount = 0

        let dict = defaults.dictionaryRepresentation()
        for (key, value) in dict {
            guard !AppDelegate.excludedKeys.contains(key) else { continue }
            guard key.hasPrefix("flutter.") else { continue } // only Flutter prefs

            // Estimate size (JSON-ish approximation)
            if let str = value as? String {
                let bytes = str.utf8.count
                if bytes > AppDelegate.maxValueBytes {
                    skippedCount += 1
                    continue
                }
                totalBytes += bytes
            }
            if totalBytes > AppDelegate.maxTotalBytes { break }

            kvStore.set(value, forKey: key)
            syncedCount += 1
        }

        kvStore.synchronize()

        if syncedCount > 0 {
            print("HuddlBackup: Synced \(syncedCount) keys to iCloud KV (\(skippedCount) skipped)")
        }
    }

    /// Pull iCloud KV values down into local SharedPreferences.
    private func pullICloudKVToLocal() {
        let defaults = UserDefaults.standard
        let kvStore  = NSUbiquitousKeyValueStore.default

        var restoredCount = 0
        let kvDict = kvStore.dictionaryRepresentation
        for (key, value) in kvDict {
            guard !AppDelegate.excludedKeys.contains(key) else { continue }
            defaults.set(value, forKey: key)
            restoredCount += 1
        }
        defaults.synchronize()

        if restoredCount > 0 {
            print("HuddlBackup: Pulled \(restoredCount) keys from iCloud KV to local storage")
        }
    }

    /// On a fresh install, if local SharedPreferences are empty but
    /// iCloud KV has data (from the user's previous device), restore it.
    private func restoreFromICloudKVIfNeeded() {
        let defaults = UserDefaults.standard
        let kvStore  = NSUbiquitousKeyValueStore.default

        // Check if there's any existing Flutter data locally
        let localHasData = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("flutter.") }
        let kvHasData    = !kvStore.dictionaryRepresentation.isEmpty

        if !localHasData && kvHasData {
            print("HuddlBackup: No local data found, restoring from iCloud KV")
            pullICloudKVToLocal()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
