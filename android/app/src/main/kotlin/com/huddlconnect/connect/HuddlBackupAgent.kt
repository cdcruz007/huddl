package com.huddlconnect.connect

import android.app.backup.BackupAgentHelper
import android.app.backup.SharedPreferencesBackupHelper
import android.app.backup.FileBackupHelper
import android.content.Context

/**
 * HUDDL — ANDROID BACKUP AGENT
 * ======================================
 * Registered in AndroidManifest.xml as android:backupAgent=".HuddlBackupAgent"
 *
 * Handles Google Cloud Backup (Android Backup Service) for:
 *  • All SharedPreferences data (via BrowserStorage / shared_preferences plugin)
 *  • Key-value store: user profile, messages, groups, meetups, events,
 *    polls, saved items, preferences, subscriptions, invitations, etc.
 *
 * The OS triggers onBackup() automatically when:
 *  - The device is idle, charging, and on Wi-Fi (typically nightly)
 *  - The user enables cloud backup in Android Settings
 *
 * The OS triggers onRestore() automatically when:
 *  - The user installs the app on a new device
 *  - The user factory-resets the device and restores from backup
 *  - The user reinstalls the app (if auto-restore is enabled)
 *
 * SharedPreferences file name = applicationId (com.huddlconnect.connect)
 * because Flutter's shared_preferences plugin uses the package name.
 */
class HuddlBackupAgent : BackupAgentHelper() {

    companion object {
        // The shared_preferences plugin stores all data in a file named after
        // the package ID. We must reference the exact filename (without .xml).
        private const val PREFS_BACKUP_KEY = "huddl_prefs_backup"
        private const val FILES_BACKUP_KEY = "huddl_files_backup"
    }

    override fun onCreate() {
        // ── SharedPreferences backup ──────────────────────────────────────
        // Flutter's shared_preferences plugin stores data in a file named
        // after the application package (com.huddlconnect.connect).
        // We register this file for cloud backup.
        val prefsFilename = packageName  // = "com.huddlconnect.connect"
        val prefsHelper = SharedPreferencesBackupHelper(this, prefsFilename)
        addHelper(PREFS_BACKUP_KEY, prefsHelper)

        // ── App files backup ─────────────────────────────────────────────
        // Back up any files written to the app's internal files directory
        // (e.g. profile photos, media attachments saved locally).
        val filesHelper = FileBackupHelper(this, ".")
        addHelper(FILES_BACKUP_KEY, filesHelper)
    }
}
