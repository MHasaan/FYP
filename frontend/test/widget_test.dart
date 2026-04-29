// Basic widget test for the FYP app

import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_frontend/main.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const FYPApp());
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
