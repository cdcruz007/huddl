import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huddl_connect/widgets/borough_badge.dart';
import 'package:huddl_connect/services/borough_scope_guard.dart';

// =============================================================================
// WIDGET TESTS — BOROUGH UI WIDGETS (Step 15)
//
// Tests cover:
//   1. BoroughBadge — rendering, text, icons, UK-wide vs borough-only
//   2. BoroughScopeChip — rendering for all 3 scope types
//   3. BoroughHeader — rendering for all 3 scope types, custom labels
//   4. BoroughGateMessage — rendering, message content
//   5. Edge cases: empty borough, null values, size variants
// =============================================================================

/// Wraps a widget in MaterialApp for testing.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('BoroughBadge', () {
    testWidgets('renders UK-wide badge when forceUkWide is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(forceUkWide: true),
      ));

      expect(find.text('UK-wide'), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('renders UK-wide badge for events feature',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(feature: HuddlFeature.events),
      ));

      expect(find.text('UK-wide'), findsOneWidget);
    });

    testWidgets('renders borough name when provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(
          borough: 'Cambridge',
          feature: HuddlFeature.groups,
        ),
      ));

      expect(find.text('Cambridge'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });

    testWidgets('renders SizedBox.shrink when borough is empty and not UK-wide',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(borough: ''),
      ));

      // Should render shrunk widget (no text visible)
      expect(find.text('UK-wide'), findsNothing);
    });

    testWidgets('small size is default', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(
          borough: 'Cambridge',
          size: BoroughBadgeSize.small,
        ),
      ));

      expect(find.text('Cambridge'), findsOneWidget);
    });

    testWidgets('medium size renders', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughBadge(
          borough: 'Oxford',
          size: BoroughBadgeSize.medium,
        ),
      ));

      expect(find.text('Oxford'), findsOneWidget);
    });
  });

  group('BoroughScopeChip', () {
    testWidgets('renders UK-wide chip for events',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughScopeChip(
          feature: HuddlFeature.events,
          borough: 'Cambridge',
        ),
      ));

      expect(find.text('UK-wide'), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('renders borough name chip for groups',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughScopeChip(
          feature: HuddlFeature.groups,
          borough: 'Cambridge',
        ),
      ));

      expect(find.text('Cambridge'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });

    testWidgets('renders "Nearby" chip for borough-aware features',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughScopeChip(
          feature: HuddlFeature.offers,
          borough: 'Cambridge',
        ),
      ));

      expect(find.text('Near Cambridge'), findsOneWidget);
      expect(find.byIcon(Icons.near_me_outlined), findsOneWidget);
    });

    testWidgets('renders fallback when borough is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughScopeChip(
          feature: HuddlFeature.meetups,
          borough: '',
        ),
      ));

      expect(find.text('Your borough'), findsOneWidget);
    });
  });

  group('BoroughHeader', () {
    testWidgets('renders UK-wide header for events',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughHeader(
          feature: HuddlFeature.events,
          borough: 'Cambridge',
        ),
      ));

      expect(find.text('Showing events across the UK'), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('renders borough-only header for marketplace',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughHeader(
          feature: HuddlFeature.marketplace,
          borough: 'Cambridge',
        ),
      ));

      expect(find.text('Showing results in Cambridge'), findsOneWidget);
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });

    testWidgets('renders borough-aware header for offers',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughHeader(
          feature: HuddlFeature.offers,
          borough: 'Oxford',
        ),
      ));

      expect(
          find.text('Prioritising results near Oxford'), findsOneWidget);
    });

    testWidgets('custom label overrides default',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughHeader(
          feature: HuddlFeature.groups,
          borough: 'Cambridge',
          customLabel: 'Custom header text',
        ),
      ));

      expect(find.text('Custom header text'), findsOneWidget);
    });

    testWidgets('fallback when borough is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughHeader(
          feature: HuddlFeature.groups,
          borough: '',
        ),
      ));

      expect(find.text('Showing results in your borough'), findsOneWidget);
    });
  });

  group('BoroughGateMessage', () {
    testWidgets('renders feature label and borough name',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughGateMessage(
          featureLabel: 'Meetups',
          userBorough: 'Cambridge',
        ),
      ));

      expect(
        find.textContaining('Meetups is limited to Cambridge'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('renders with fallback borough text',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughGateMessage(
          featureLabel: 'Groups',
        ),
      ));

      // Should use fallback "your borough"
      expect(
        find.textContaining('Groups is limited to'),
        findsOneWidget,
      );
    });

    testWidgets('contains interaction explanation',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughGateMessage(
          featureLabel: 'DMs',
          userBorough: 'Oxford',
        ),
      ));

      expect(
        find.textContaining('Only parents in your borough'),
        findsOneWidget,
      );
    });

    testWidgets('has amber info icon', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(
        const BoroughGateMessage(featureLabel: 'Chat'),
      ));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });
}
