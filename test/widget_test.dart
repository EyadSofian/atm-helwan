// Basic smoke test for ATM Helwan app.

import 'package:flutter_test/flutter_test.dart';

import 'package:atm_helwan/main.dart';

void main() {
  testWidgets('AtmHelwanApp can be instantiated', (WidgetTester tester) async {
    // Verify the root widget can be created without errors.
    await tester.pumpWidget(const AtmHelwanApp());
    expect(find.byType(AtmHelwanApp), findsOneWidget);
  });
}
