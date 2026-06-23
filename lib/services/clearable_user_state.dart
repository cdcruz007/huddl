import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Services holding user-specific in-memory + persisted state implement this
/// so [signOut()] can wipe everything tied to the outgoing user.
///
/// Contract:
///   • Clear ALL in-memory fields bound to the current user.
///   • Remove every BrowserStorage key written on behalf of this user.
///   • Cancel any active timers or stream subscriptions tied to this user.
///   • Must not throw — swallow and log internally if needed; the registry
///     catches any escaping exceptions anyway.
abstract class ClearableUserState {
  /// Clear ALL state tied to the current user: in-memory fields,
  /// backing BrowserStorage keys, and any active timers/subscriptions.
  Future<void> clearUserState();
}

/// Central registry for [ClearableUserState] implementations.
///
/// Stateful singletons call [register(this)] in their private constructor.
/// [signOut()] calls [clearAll()] once — every registered service is wiped.
///
/// Design notes:
///   • Self-registering: new services cannot be forgotten in a hand-maintained
///     sign-out list; they just implement the interface and call register().
///   • Fail-safe: one service throwing must not prevent the rest from clearing.
///     Each service is wrapped in try/catch; errors are logged to Crashlytics.
///   • Idempotent register: duplicate registrations are silently ignored.
class UserStateRegistry {
  UserStateRegistry._(); // no instances

  static final List<ClearableUserState> _services = [];

  /// Register a service. Safe to call multiple times — duplicates are ignored.
  static void register(ClearableUserState s) {
    if (!_services.contains(s)) _services.add(s);
  }

  /// Clears all registered services. Call from [signOut()] and account-delete
  /// paths. One service failing does not block the rest.
  static Future<void> clearAll() async {
    for (final s in _services) {
      try {
        await s.clearUserState();
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'UserStateRegistry.clearAll: ${s.runtimeType}.clearUserState failed',
          fatal: false,
        );
        // continue — one service failing must not block clearing the rest
      }
    }
  }
}
