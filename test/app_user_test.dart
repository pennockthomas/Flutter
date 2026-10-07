import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppUser.clearForTest();
  });

  test('there is no name until one is entered', () {
    expect(AppUser.hasName, isFalse);
    expect(AppUser.name, '');
    expect(AppUser.displayName, 'You');
    expect(AppUser.initials, '?');
  });

  test('a saved name is used, trimmed and with spaces tidied', () async {
    expect(await AppUser.setName('  Thomas   Pennock '), isTrue);

    expect(AppUser.name, 'Thomas Pennock');
    expect(AppUser.firstName, 'Thomas');
  });

  test('initials are the first letter of the first and last word', () async {
    await AppUser.setName('Thomas Pennock');
    expect(AppUser.initials, 'TP');

    await AppUser.setName('mila van der vermeer');
    expect(AppUser.initials, 'MV');

    await AppUser.setName('Sam');
    expect(AppUser.initials, 'S');
  });

  test('the name survives a restart', () async {
    await AppUser.setName('Lena Bakker');
    AppUser.clearForTest();

    await AppUser.load();

    expect(AppUser.name, 'Lena Bakker');
  });

  test(
    'empty, blank, too long and control-character names are refused',
    () async {
      await AppUser.setName('Sam');

      expect(await AppUser.setName(''), isFalse);
      expect(await AppUser.setName('   '), isFalse);
      expect(await AppUser.setName('x' * (AppUser.maxNameLength + 1)), isFalse);
      expect(await AppUser.setName('Sam\u0007'), isFalse);
      expect(AppUser.name, 'Sam', reason: 'a refused name changes nothing');
    },
  );

  test('a name of exactly the longest allowed length is accepted', () async {
    expect(await AppUser.setName('x' * AppUser.maxNameLength), isTrue);
  });

  test('listeners hear about a new name', () async {
    final heard = <String>[];
    AppUser.listenable.addListener(() => heard.add(AppUser.name));

    await AppUser.setName('Sam');
    await AppUser.setName('Sam de Vries');

    expect(heard, ['Sam', 'Sam de Vries']);
  });
}
