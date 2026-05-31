# ─────────────────────────────────────────────────────────────────────────────
# Huddl — ProGuard / R8 keep rules
# Applied when isMinifyEnabled = true in release buildType.
# ─────────────────────────────────────────────────────────────────────────────

# ── Flutter engine ───────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# ── Firebase / Google Play Services ─────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Stripe ───────────────────────────────────────────────────────────────────
-keep class com.stripe.** { *; }
-dontwarn com.stripe.**

# ── audioplayers ─────────────────────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# ── record (audio recording) ─────────────────────────────────────────────────
-keep class com.llfbandit.record.** { *; }
-dontwarn com.llfbandit.record.**

# ── Huddl application classes ────────────────────────────────────────────────
-keep class com.huddlconnect.** { *; }

# ── Keep Parcelable / Serializable model classes ─────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── OkHttp (used by Firebase + Stripe) ───────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ── Kotlin coroutines ────────────────────────────────────────────────────────
-keepclassmembernames class kotlinx.** {
    volatile <fields>;
}
