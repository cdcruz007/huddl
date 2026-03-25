import 'package:flutter_test/flutter_test.dart';
import 'package:huddl_connect/main.dart';

void main() {
  testWidgets('HuddlApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HuddlApp());
    expect(find.byType(HuddlApp), findsOneWidget);
  });
}
