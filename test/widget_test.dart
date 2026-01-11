import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickman_3d/stickman_3d.dart';
import '../lib/main.dart'; // Import relative to test folder, assuming main.dart is in lib

void main() {
  testWidgets('Stickman Demo smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title text is present.
    expect(find.text('Stickman 3D Demo'), findsOneWidget);

    // Check if CustomPaint is present
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
