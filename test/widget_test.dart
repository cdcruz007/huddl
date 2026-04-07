import 'package:flutter_test/flutter_test.dart';
import 'package:huddl_connect/main.dart';

void main() {
  testWidgets('HuddlApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HuddlApp());
    // Only verify initial render — don't wait for timers/animations
    // since the splash screen has running timers that persist.
    expect(find.byType(HuddlApp), findsOneWidget);
    // Pump remaining frames and timers to avoid "Timer still pending" error
    await tester.pump(const Duration(seconds: 10));
  });
}
