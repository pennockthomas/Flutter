// The main screen's bottom tab bar: shows the three tabs, marks the current
// one as selected, and reports taps.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flut/app_shell.dart';

void main() {
  testWidgets('ShellTabBar shows Tree, QuickSwipe and Progress and reports taps',
      (WidgetTester tester) async {
    final selected = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ShellTabBar(
            currentIndex: 0,
            onSelect: selected.add,
          ),
        ),
      ),
    );

    expect(find.text('Tree'), findsOneWidget);
    expect(find.text('QuickSwipe'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);

    await tester.tap(find.text('Progress'));
    await tester.tap(find.text('QuickSwipe'));
    await tester.pump();

    expect(selected, [2, 1]);
  });

  testWidgets('ShellTabBar marks only the current tab as selected',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ShellTabBar(currentIndex: 1, onSelect: (_) {}),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('QuickSwipe')),
      containsSemantics(label: 'QuickSwipe', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tree')),
      containsSemantics(label: 'Tree', isButton: true, isSelected: false),
    );
  });
}
