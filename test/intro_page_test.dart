// The first-run intro: pages advance with Next, finishing (or skipping)
// saves the seen-flag and hands control back via onFinished.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_settings.dart';
import 'package:flut/intro_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpIntro(WidgetTester tester, VoidCallback onFinished) {
    return tester.pumpWidget(
      MaterialApp(home: IntroPage(onFinished: onFinished)),
    );
  }

  testWidgets('Next walks through all pages, then Get started finishes', (
    tester,
  ) async {
    var finished = 0;
    await pumpIntro(tester, () => finished++);

    expect(find.text('Swap plastic for things that last'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Grow your tree'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Count what you already do'), findsOneWidget);
    expect(finished, 0);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(finished, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppSettingKeys.introSeen), isTrue);
    expect(await IntroPage.hasBeenSeen(), isTrue);
  });

  testWidgets('Skip finishes immediately and marks the intro seen', (
    tester,
  ) async {
    var finished = 0;
    await pumpIntro(tester, () => finished++);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(finished, 1);
    expect(await IntroPage.hasBeenSeen(), isTrue);
  });

  test('not seen by default', () async {
    expect(await IntroPage.hasBeenSeen(), isFalse);
  });
}
