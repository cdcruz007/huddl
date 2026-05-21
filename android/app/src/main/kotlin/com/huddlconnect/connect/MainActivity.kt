package com.huddlconnect.connect

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createHuddlNotificationChannels()
        }
    }

    // ── Create all 7 Huddl notification channels ──────────────────────────────
    //
    // Channels must be created before any notification is posted on Android 8+.
    // Creating a channel that already exists is a no-op, so this is safe to call
    // on every launch.
    //
    // Channel IDs mirror HuddlChannels constants in notification_copy_service.dart.
    // Importance levels: IMPORTANCE_HIGH (4) = heads-up, IMPORTANCE_DEFAULT (3) = sound.
    //
    private fun createHuddlNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        val channels = listOf(
            Triple(
                "huddl_group_messages",
                "Group Messages",
                NotificationManager.IMPORTANCE_HIGH
            ) to "New messages in groups you've joined",

            Triple(
                "huddl_dm_messages",
                "Direct Messages",
                NotificationManager.IMPORTANCE_HIGH
            ) to "Private messages from other parents",

            Triple(
                "huddl_meetup_updates",
                "Meet-up Updates",
                NotificationManager.IMPORTANCE_HIGH
            ) to "Reminders and changes to meet-ups you're attending",

            Triple(
                "huddl_market_alerts",
                "Market Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ) to "Offers received on your listings and items you've saved",

            Triple(
                "huddl_community_posts",
                "Community Posts",
                NotificationManager.IMPORTANCE_DEFAULT
            ) to "New posts and replies in your local community feed",

            Triple(
                "huddl_send_alerts",
                "SEND Support",
                NotificationManager.IMPORTANCE_HIGH
            ) to "Deadline reminders and updates for SEND support tasks",

            Triple(
                "huddl_system_alerts",
                "Huddl Updates",
                NotificationManager.IMPORTANCE_DEFAULT
            ) to "Important account and app updates from Huddl",
        )

        for ((triple, description) in channels) {
            val (id, name, importance) = triple
            val channel = NotificationChannel(id, name, importance).apply {
                this.description = description
                enableLights(true)
                enableVibration(importance == NotificationManager.IMPORTANCE_HIGH)
            }
            nm.createNotificationChannel(channel)
        }
    }
}
