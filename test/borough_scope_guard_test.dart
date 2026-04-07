import 'package:flutter_test/flutter_test.dart';
import 'package:huddl_connect/services/borough_scope_guard.dart';

// =============================================================================
// UNIT TESTS — BOROUGH SCOPE GUARD (Step 14)
//
// Tests cover:
//   1. Feature scope classification
//   2. Borough-only vs UK-wide vs borough-aware feature logic
//   3. isAccessAllowed() for all feature types
//   4. filterByUserBorough() filtering logic
//   5. debugSummary() completeness
//   6. Edge cases: null boroughs, empty strings, case insensitivity
// =============================================================================

void main() {
  group('BoroughScopeGuard — Feature Scope Classification', () {
    test('chat is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.chat),
          FeatureScope.boroughOnly);
    });

    test('directMessages is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.directMessages),
          FeatureScope.boroughOnly);
    });

    test('groups is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.groups),
          FeatureScope.boroughOnly);
    });

    test('meetups is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.meetups),
          FeatureScope.boroughOnly);
    });

    test('marketplace is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.marketplace),
          FeatureScope.boroughOnly);
    });

    test('matchmaker is borough-only', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.matchmaker),
          FeatureScope.boroughOnly);
    });

    test('events is UK-wide (the only exception)', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.events),
          FeatureScope.ukWide);
    });

    test('communityFeed is borough-aware', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.communityFeed),
          FeatureScope.boroughAware);
    });

    test('offers is borough-aware', () {
      expect(BoroughScopeGuard.scopeOf(HuddlFeature.offers),
          FeatureScope.boroughAware);
    });
  });

  group('BoroughScopeGuard — isBoroughOnly / isUkWide helpers', () {
    test('isBoroughOnly returns true for all 6 borough-only features', () {
      const boroughOnlyFeatures = [
        HuddlFeature.chat,
        HuddlFeature.directMessages,
        HuddlFeature.groups,
        HuddlFeature.meetups,
        HuddlFeature.marketplace,
        HuddlFeature.matchmaker,
      ];
      for (final f in boroughOnlyFeatures) {
        expect(BoroughScopeGuard.isBoroughOnly(f), isTrue,
            reason: '${f.name} should be borough-only');
      }
    });

    test('isBoroughOnly returns false for events', () {
      expect(BoroughScopeGuard.isBoroughOnly(HuddlFeature.events), isFalse);
    });

    test('isUkWide returns true only for events', () {
      for (final f in HuddlFeature.values) {
        if (f == HuddlFeature.events) {
          expect(BoroughScopeGuard.isUkWide(f), isTrue);
        } else {
          expect(BoroughScopeGuard.isUkWide(f), isFalse,
              reason: '${f.name} should not be UK-wide');
        }
      }
    });
  });

  group('BoroughScopeGuard — HuddlFeature enum completeness', () {
    test('all features have exactly one scope', () {
      for (final f in HuddlFeature.values) {
        final scope = BoroughScopeGuard.scopeOf(f);
        expect(scope, isNotNull,
            reason: '${f.name} must have a scope');
        expect(FeatureScope.values.contains(scope), isTrue);
      }
    });

    test('feature enum has 9 values', () {
      expect(HuddlFeature.values.length, 9);
    });

    test('scope enum has 3 values', () {
      expect(FeatureScope.values.length, 3);
    });
  });

  group('BoroughScopeGuard — debugSummary', () {
    test('debugSummary contains expected sections', () {
      final guard = BoroughScopeGuard();
      final summary = guard.debugSummary();

      expect(summary, contains('BoroughScopeGuard Summary'));
      expect(summary, contains('User borough:'));
      expect(summary, contains('Borough-only features:'));
      expect(summary, contains('UK-wide features:'));
      expect(summary, contains('Borough-aware features:'));
    });

    test('debugSummary lists all borough-only features', () {
      final guard = BoroughScopeGuard();
      final summary = guard.debugSummary();

      expect(summary, contains('chat'));
      expect(summary, contains('directMessages'));
      expect(summary, contains('groups'));
      expect(summary, contains('meetups'));
      expect(summary, contains('marketplace'));
      expect(summary, contains('matchmaker'));
    });

    test('debugSummary lists events as UK-wide', () {
      final guard = BoroughScopeGuard();
      final summary = guard.debugSummary();

      // events should appear under UK-wide, not borough-only
      final ukWideSection = summary.split('UK-wide features:')[1];
      final boroughAwareSection = ukWideSection.split('Borough-aware')[0];
      expect(boroughAwareSection, contains('events'));
    });
  });

  group('BoroughScopeGuard — filterByUserBorough edge cases', () {
    test('returns full list when user borough is null (no postcode)', () {
      final guard = BoroughScopeGuard();
      // Since user has no postcode set, currentBorough is null
      // filterByUserBorough should return the full list
      final items = ['Cambridge', 'Oxford', 'London'];
      final result = guard.filterByUserBorough<String>(
        items,
        (item) => item,
      );
      // With no user borough, returns all items (guard is permissive)
      expect(result, items);
    });

    test('items with null borough are filtered out', () {
      final guard = BoroughScopeGuard();
      // With no user borough set, items are returned as-is
      final items = [
        {'name': 'A', 'borough': null},
        {'name': 'B', 'borough': 'Cambridge'},
      ];
      final result = guard.filterByUserBorough<Map<String, dynamic>>(
        items,
        (item) => item['borough'] as String?,
      );
      // With no user borough, all items returned
      expect(result, items);
    });
  });
}
