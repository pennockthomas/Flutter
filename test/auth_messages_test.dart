// The short, readable messages shown on the sign-in screen: Firebase's own
// messages can be long and technical, so every case should map to one of ours.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flut/auth_service.dart';

String _message(String code, [String? firebaseMessage]) => AuthService.instance
    .messageFor(FirebaseAuthException(code: code, message: firebaseMessage));

void main() {
  test('known sign-in mistakes get a plain message', () {
    expect(_message('invalid-credential'), 'Incorrect email or password.');
    expect(_message('wrong-password'), 'Incorrect email or password.');
    expect(_message('email-already-in-use'), contains('already exists'));
    expect(_message('weak-password'), contains('6 characters'));
    expect(_message('network-request-failed'), contains('internet'));
    expect(_message('too-many-requests'), contains('Too many attempts'));
  });

  test('an account setup problem on the server is explained, not dumped', () {
    final message = _message(
      'internal-error',
      '{"error":{"code":400,"message":"CONFIGURATION_NOT_FOUND"}}',
    );

    expect(message, "Accounts aren't set up for this app yet.");
  });

  test('email sign-in being switched off is explained', () {
    expect(_message('operation-not-allowed'), contains("isn't turned on"));
  });

  test('other internal errors do not show Firebase text', () {
    final message = _message('internal-error', 'NSUnderlyingError=0x12e134f60');

    expect(message, isNot(contains('NSUnderlyingError')));
  });

  test('an unknown error code falls back to a generic message', () {
    final message = _message('some-new-code', 'A very long technical message');

    expect(message, 'Something went wrong. Try again.');
  });
}
