import 'browser_storage.dart';

/// Singleton that holds the user's privacy and notification preferences.
///
/// Usage:
///   await UserPrivacyPrefsService().load();        // call once on startup / login
///   UserPrivacyPrefsService().showOnlineStatus     // read anywhere
///   await UserPrivacyPrefsService().setSetting(key, value); // write from profile
class UserPrivacyPrefsService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final UserPrivacyPrefsService _instance =
      UserPrivacyPrefsService._internal();
  factory UserPrivacyPrefsService() => _instance;
  UserPrivacyPrefsService._internal();

  // ── Storage keys ───────────────────────────────────────────────────────
  static const String keyPushEnabled       = 'pref_push_enabled';
  static const String keyGroupMessages     = 'pref_group_messages';
  static const String keyDmMessages        = 'pref_dm_messages';
  static const String keyEventReminders    = 'pref_event_reminders';
  static const String keyCommunityUpdates  = 'pref_community_updates';
  static const String keyShowOnline        = 'pref_show_online';
  static const String keyShowProfile       = 'pref_show_profile';
  static const String keyShowGroups        = 'pref_show_groups';
  static const String keyReadReceipts      = 'pref_read_receipts';

  // ── Notification prefs (default: all enabled) ─────────────────────────
  bool pushEnabled      = true;
  bool groupMessages    = true;
  bool dmMessages       = true;
  bool eventReminders   = true;
  bool communityUpdates = true;

  // ── Privacy prefs (default: all enabled) ──────────────────────────────
  bool showOnlineStatus   = true;
  bool profileVisibility  = true;
  bool showGroups         = true;
  bool readReceipts       = true;

  // ── Load from storage ─────────────────────────────────────────────────
  Future<void> load() async {
    final nPush   = await BrowserStorage.getString(keyPushEnabled);
    final nGroup  = await BrowserStorage.getString(keyGroupMessages);
    final nDM     = await BrowserStorage.getString(keyDmMessages);
    final nEvent  = await BrowserStorage.getString(keyEventReminders);
    final nComm   = await BrowserStorage.getString(keyCommunityUpdates);
    final pOnline = await BrowserStorage.getString(keyShowOnline);
    final pProf   = await BrowserStorage.getString(keyShowProfile);
    final pGrps   = await BrowserStorage.getString(keyShowGroups);
    final pRead   = await BrowserStorage.getString(keyReadReceipts);

    if (nPush   != null) pushEnabled      = nPush   == 'true';
    if (nGroup  != null) groupMessages    = nGroup  == 'true';
    if (nDM     != null) dmMessages       = nDM     == 'true';
    if (nEvent  != null) eventReminders   = nEvent  == 'true';
    if (nComm   != null) communityUpdates = nComm   == 'true';
    if (pOnline != null) showOnlineStatus = pOnline == 'true';
    if (pProf   != null) profileVisibility = pProf  == 'true';
    if (pGrps   != null) showGroups       = pGrps   == 'true';
    if (pRead   != null) readReceipts     = pRead   == 'true';
  }

  // ── Write a single setting ─────────────────────────────────────────────
  Future<void> setSetting(String key, bool value) async {
    await BrowserStorage.setString(key, value.toString());
    // Keep in-memory cache up-to-date
    switch (key) {
      case keyPushEnabled:      pushEnabled      = value; break;
      case keyGroupMessages:    groupMessages    = value; break;
      case keyDmMessages:       dmMessages       = value; break;
      case keyEventReminders:   eventReminders   = value; break;
      case keyCommunityUpdates: communityUpdates = value; break;
      case keyShowOnline:       showOnlineStatus = value; break;
      case keyShowProfile:      profileVisibility = value; break;
      case keyShowGroups:       showGroups       = value; break;
      case keyReadReceipts:     readReceipts     = value; break;
    }
  }

  // ── Reset all (called on logout / account deletion) ───────────────────
  void reset() {
    pushEnabled      = true;
    groupMessages    = true;
    dmMessages       = true;
    eventReminders   = true;
    communityUpdates = true;
    showOnlineStatus = true;
    profileVisibility = true;
    showGroups       = true;
    readReceipts     = true;
  }
}
