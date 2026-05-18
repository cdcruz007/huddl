import 'package:flutter/foundation.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// BOROUGH SCOPE GUARD — HYPERLOCAL ENFORCEMENT LAYER (Step 5)
//
// Central utility that every data service uses to enforce borough isolation.
//
// HYPERLOCAL CONTRACT:
//   Borough-only features  →  Chat, DMs, Groups, Meetups, Marketplace, Matchmaker
//   UK-wide features       →  Events (the ONLY cross-borough feature)
//
// This guard provides:
//   1. Current user borough resolution (single source of truth)
//   2. Borough-match checks for filtering data
//   3. Logging for blocked cross-borough attempts
//   4. Feature-scope classification (borough-only vs UK-wide)
//
// All services MUST call through this guard rather than rolling their own
// borough resolution logic. This guarantees a single enforcement point.
// =============================================================================

/// Features that are restricted to the user's home borough.
/// Events are explicitly excluded — they are UK-wide.
enum HuddlFeature {
  chat,
  directMessages,
  groups,
  meetups,
  marketplace,
  matchmaker,
  events, // UK-wide — the only exception
  communityFeed, // Borough-aware (shows local content, but events can cross)
  offers, // Borough-aware (local deals ranked higher)
  services, // Borough-only — local services directory
}

/// Scope classification for a feature.
enum FeatureScope {
  boroughOnly,
  ukWide,
  boroughAware, // Primarily local, but some cross-borough elements allowed
}

/// Central borough-scoping guard for the Huddl app.
///
/// Singleton — shared across all services that need borough enforcement.
class BoroughScopeGuard {
  static final BoroughScopeGuard _instance = BoroughScopeGuard._internal();
  factory BoroughScopeGuard() => _instance;
  BoroughScopeGuard._internal();

  final PostcodeService _postcode = PostcodeService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  // ── Feature scope map ──────────────────────────────────────────────────

  /// Returns the scope classification for a given feature.
  static FeatureScope scopeOf(HuddlFeature feature) {
    switch (feature) {
      case HuddlFeature.chat:
      case HuddlFeature.directMessages:
      case HuddlFeature.groups:
      case HuddlFeature.meetups:
      case HuddlFeature.marketplace:
      case HuddlFeature.matchmaker:
      case HuddlFeature.services:
        return FeatureScope.boroughOnly;
      case HuddlFeature.events:
        return FeatureScope.ukWide;
      case HuddlFeature.communityFeed:
      case HuddlFeature.offers:
        return FeatureScope.boroughAware;
    }
  }

  /// Whether a feature is strictly borough-only.
  static bool isBoroughOnly(HuddlFeature feature) =>
      scopeOf(feature) == FeatureScope.boroughOnly;

  /// Whether a feature is UK-wide (currently only Events).
  static bool isUkWide(HuddlFeature feature) =>
      scopeOf(feature) == FeatureScope.ukWide;

  // ── User borough resolution (single source of truth) ──────────────────

  /// Returns the current user's borough, derived from their onboarding
  /// postcode. Returns null if the user hasn't set a postcode yet.
  String? get currentBorough {
    final pc = _onboarding.postcode;
    if (pc == null || pc.isEmpty) return null;
    return _postcode.getBoroughFromPostcode(pc);
  }

  /// Same as [currentBorough] but with a fallback value.
  String currentBoroughOr(String fallback) => currentBorough ?? fallback;

  // ── Borough-match checks ──────────────────────────────────────────────

  /// Returns true if [candidateBorough] matches the current user's borough
  /// (case-insensitive). Returns false if either borough is null/empty.
  bool isSameBorough(String? candidateBorough) {
    final userBorough = currentBorough;
    if (userBorough == null || userBorough.isEmpty) return false;
    if (candidateBorough == null || candidateBorough.isEmpty) return false;
    return userBorough.toLowerCase() == candidateBorough.toLowerCase();
  }

  /// Returns true if the user is allowed to access data tagged with
  /// [dataBorough] for the given [feature].
  ///
  /// - Borough-only features: only if boroughs match
  /// - UK-wide features: always allowed
  /// - Borough-aware features: always allowed (but caller may rank local higher)
  bool isAccessAllowed({
    required HuddlFeature feature,
    required String? dataBorough,
  }) {
    switch (scopeOf(feature)) {
      case FeatureScope.ukWide:
      case FeatureScope.boroughAware:
        return true;
      case FeatureScope.boroughOnly:
        return isSameBorough(dataBorough);
    }
  }

  // ── Filtering helpers ─────────────────────────────────────────────────

  /// Filters a list of items to only those in the user's borough.
  /// [boroughExtractor] pulls the borough string from each item.
  /// Used by services like Marketplace, Meetups, Groups.
  List<T> filterByUserBorough<T>(
    List<T> items,
    String? Function(T item) boroughExtractor,
  ) {
    final userBorough = currentBorough;
    if (userBorough == null || userBorough.isEmpty) return items;
    final lowerBorough = userBorough.toLowerCase();

    return items.where((item) {
      final itemBorough = boroughExtractor(item);
      if (itemBorough == null || itemBorough.isEmpty) {
        // Items without a borough tag are shown rather than hidden — they were
        // likely loaded from Firestore before the borough field was written, or
        // created by a user whose postcode lookup hasn't resolved yet.  Hiding
        // them produces a blank marketplace / empty meetup list on first open,
        // which is a worse UX than showing a slightly wider set of results.
        return true;
      }
      return itemBorough.toLowerCase() == lowerBorough;
    }).toList();
  }

  /// Checks if the current user can interact with a specific entity
  /// (e.g. send DM to another user, join a group). Logs a warning
  /// and returns false if the borough doesn't match.
  bool canInteract({
    required HuddlFeature feature,
    required String? targetBorough,
    String? targetName,
  }) {
    if (isAccessAllowed(feature: feature, dataBorough: targetBorough)) {
      return true;
    }

    _logBlocked(
      feature: feature,
      targetBorough: targetBorough,
      targetName: targetName,
    );
    return false;
  }

  // ── Logging ───────────────────────────────────────────────────────────

  void _logBlocked({
    required HuddlFeature feature,
    String? targetBorough,
    String? targetName,
  }) {
    if (kDebugMode) {
      debugPrint(
        'BoroughScopeGuard: BLOCKED cross-borough access'
        ' — feature=${feature.name}'
        ', userBorough=$currentBorough'
        ', targetBorough=$targetBorough'
        '${targetName != null ? ", target=$targetName" : ""}',
      );
    }
  }

  // ── Debug / introspection ─────────────────────────────────────────────

  /// Returns a human-readable summary of the current guard state.
  /// Useful in debug overlays and system prompt builders.
  String debugSummary() {
    final sb = StringBuffer();
    sb.writeln('BoroughScopeGuard Summary');
    sb.writeln('  User borough: ${currentBorough ?? "not set"}');
    sb.writeln('  Borough-only features:');
    for (final f in HuddlFeature.values) {
      if (isBoroughOnly(f)) sb.writeln('    - ${f.name}');
    }
    sb.writeln('  UK-wide features:');
    for (final f in HuddlFeature.values) {
      if (isUkWide(f)) sb.writeln('    - ${f.name}');
    }
    sb.writeln('  Borough-aware features:');
    for (final f in HuddlFeature.values) {
      if (scopeOf(f) == FeatureScope.boroughAware) {
        sb.writeln('    - ${f.name}');
      }
    }
    return sb.toString();
  }
}
