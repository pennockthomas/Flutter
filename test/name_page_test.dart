// The first-launch "what should we call you?" screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';
import 'package:flut/name_page.dart';

Future<void> _show(WidgetTester tester, VoidCallback onFinished) async {
  await tester.pumpWidget(MaterialApp(home: NamePage(onFinished: onFinished)));
  await tester.pump();
}

FilledButton _continueButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUser.clearForTest();
  });

  testWidgets('Continue stays off until a name is typed', (tester) async {
    await _show(tester, () {});

    expect(_continueButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_continueButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump();
    expect(_continueButton(tester).onPressed, isNotNull);
  });

  testWidgets('Continue saves the name and moves on', (tester) async {
    var finished = 0;
    await _show(tester, () => finished++);

    await tester.enterText(find.byType(TextField), '  Mila  Vermeer ');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(AppUser.name, 'Mila Vermeer');
    expect(finished, 1);
  });

  testWidgets('pressing done on the keyboard also continues', (tester) async {
    var finished = 0;
    await _show(tester, () => finished++);

    await tester.enterText(find.byType(TextField), 'Lena');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(AppUser.name, 'Lena');
    expect(finished, 1);
  });

  testWidgets('the edit dialog changes the name and Cancel does not', (
    tester,
  ) async {
    await AppUser.setName('Sam');
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );

    showEditNameDialog(context);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Someone Else');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(AppUser.name, 'Sam');

    showEditNameDialog(context);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam de Vries');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(AppUser.name, 'Sam de Vries');
  });
}
