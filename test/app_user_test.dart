import 'package:flutter_test/flutter_test.dart';

import 'package:flut/app_user.dart';

void main() {
  test('firstName is the first word of name', () {
    expect(AppUser.firstName, 'Thomas');
  });

  test('initials are the uppercase first letter of each word in name', () {
    expect(AppUser.initials, 'TP');
  });
}
