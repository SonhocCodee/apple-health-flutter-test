import 'package:flutter_test/flutter_test.dart';
import 'package:health_test_app/main.dart';

void main() {
  testWidgets('renders the Apple Health dashboard', (tester) async {
    await tester.pumpWidget(const AppleHealthTestApp());

    expect(find.text('Apple Health'), findsOneWidget);
  });
}
