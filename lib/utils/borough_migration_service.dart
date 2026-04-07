import '../services/borough_scope_guard.dart';
import '../services/announcement_service.dart';
import '../services/community_feed_service.dart';
import '../services/invitation_service.dart';
import '../services/dm_service.dart';
import '../services/onboarding_data_service.dart';
import '../services/postcode_service.dart';
import '../services/browser_storage.dart';

// =============================================================================
// BOROUGH MIGRATION SERVICE (Step 9)
//
// Centralised cascade for borough changes. When a user changes their
// postcode, this service notifies every borough-scoped service so they
// can refresh filtered data, re-resolve the borough, or clear stale
// caches. Ensures the BoroughScopeGuard's currentBorough always
// reflects the latest postcode.
// =============================================================================

class BoroughMigrationService {
  BoroughMigrationService._();
  static final BoroughMigrationService _instance = BoroughMigrationService._();
  factory BoroughMigrationService() => _instance;

  static const String _previousBoroughKey = 'borough_migration_previous';
  static const String _migrationTimestampKey = 'borough_migration_timestamp';

  /// Records the user's current borough before a change, so we can
  /// identify stale data tagged with the old borough.
  String? _previousBorough;
  String? get previousBorough => _previousBorough;

  /// Performs a full borough migration cascade.
  ///
  /// Call this AFTER the postcode has been updated in [OnboardingDataService].
  /// [newPostcode] is the validated new postcode.
  /// [previousBoroughName] is the old borough (before the change).
  ///
  /// Returns the resolved new borough name.
  Future<String> migrate({
    required String newPostcode,
    required String previousBoroughName,
  }) async {
    final newBorough =
        PostcodeService().getBoroughFromPostcode(newPostcode) ?? 'Unknown';

    // 1. Store previous borough for rollback / leave-group UI
    _previousBorough = previousBoroughName;
    await BrowserStorage.setString(_previousBoroughKey, previousBoroughName);
    await BrowserStorage.setString(
        _migrationTimestampKey, DateTime.now().toIso8601String());

    // 2. Guard picks up the new borough automatically (it reads from
    //    OnboardingDataService.postcode which was already updated).
    //    But we verify it here:
    final guard = BoroughScopeGuard();
    assert(
      guard.currentBorough?.toLowerCase() == newBorough.toLowerCase(),
      'BoroughScopeGuard.currentBorough should match new borough after '
      'postcode update. Got: ${guard.currentBorough}, expected: $newBorough',
    );

    // 3. Cascade re-initialization to all borough-scoped services.
    //    Each service re-resolves its internal _userBorough / filtered data.
    await _cascadeRefresh();

    // 4. Persist the borough in cache for instant access on cold start
    await BrowserStorage.setString('cached_borough', newBorough);

    return newBorough;
  }

  /// Re-initializes all borough-scoped services so they pick up the new
  /// postcode/borough from OnboardingDataService.
  Future<void> _cascadeRefresh() async {
    // These services read the postcode from OnboardingDataService during
    // initialize(), so calling initialize() again forces them to re-resolve
    // the borough and re-filter their data.
    try {
      await AnnouncementService().initialize();
    } catch (_) {}
    try {
      await CommunityFeedService().initialize();
    } catch (_) {}
    try {
      await InvitationService().initialize();
    } catch (_) {}
    try {
      await DMService().initialize();
    } catch (_) {}
    // MeetupService is a ChangeNotifier — its meetups getter already
    // uses the guard, so it'll return borough-filtered data automatically.
    // DefaultGroupService re-init is handled by the caller (profile screen).
  }

  /// Loads the previous borough from storage (used on cold start to
  /// detect if a migration happened in a previous session).
  Future<void> loadPreviousMigration() async {
    _previousBorough =
        await BrowserStorage.getString(_previousBoroughKey);
  }

  /// Clears migration state (e.g. after user has dismissed the
  /// leave-old-groups sheet).
  Future<void> clearMigrationState() async {
    _previousBorough = null;
    await BrowserStorage.remove(_previousBoroughKey);
    await BrowserStorage.remove(_migrationTimestampKey);
  }
}
