import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flut/main.dart';

void main() {
  testWidgets('GlassButton shows its label and responds to taps',
      (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassButton(
            text: 'Start',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
