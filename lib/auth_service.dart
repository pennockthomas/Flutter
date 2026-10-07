import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thin wrapper around [FirebaseAuth]. Accounts are entirely additive to
/// EcoSteps — every screen must keep working when [currentUser] is null.
///
/// See AI_LOG.md, "Phase 3 scoping", for the overall plan this is part of.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Whether Firebase started. It doesn't when the project isn't configured
  /// for the platform or startup failed; the app then runs local-only and
  /// accounts simply aren't offered.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  User? get currentUser => isAvailable ? _auth.currentUser : null;

  Stream<User?> get authStateChanges =>
      isAvailable ? _auth.authStateChanges() : Stream.value(null);

  Future<void> signOut() => _auth.signOut();

  /// Signs in with an email/password account, creating one first if
  /// [isRegistering] is true.
  Future<void> signInWithEmail({
    required String email,
    required String password,
    required bool isRegistering,
  }) async {
    if (isRegistering) {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } else {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  /// Native "Sign in with Apple" flow, verified through Firebase Auth.
  /// Requires the `com.apple.developer.applesignin` entitlement (see
  /// `ios/Runner/Runner.entitlements`) and the capability enabled on the
  /// App ID in the Apple Developer portal.
  Future<void> signInWithApple() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final oauthCredential = OAuthProvider(
      'apple.com',
    ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

    final userCredential = await _auth.signInWithCredential(oauthCredential);

    // Apple only returns the name on the very first authorization ever
    // granted to this app; Firebase doesn't pick it up automatically.
    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    if (givenName != null || familyName != null) {
      final fullName = [
        givenName,
        familyName,
      ].where((part) => part != null && part.isNotEmpty).join(' ');
      if (fullName.isNotEmpty &&
          (userCredential.user?.displayName == null ||
              userCredential.user!.displayName!.isEmpty)) {
        await userCredential.user?.updateDisplayName(fullName);
      }
    }
  }

  /// Turns a [FirebaseAuthException] into a short message safe to show in
  /// the sign-in UI.
  String messageFor(Object error) {
    if (error is SignInWithAppleAuthorizationException) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return 'Sign in with Apple was canceled.';
      }
      return 'Sign in with Apple failed. Try again.';
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address doesn\'t look right.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists with that email.';
        case 'weak-password':
          return 'Choose a password with at least 6 characters.';
        case 'network-request-failed':
          return 'No internet connection. Try again.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a moment and try again.';
        case 'operation-not-allowed':
          return 'Signing in with email isn\'t turned on for this app yet.';
        case 'internal-error':
          // Firebase wraps server-side setup problems in this code; the
          // useful part is buried in the message.
          if ((error.message ?? '').contains('CONFIGURATION_NOT_FOUND')) {
            return 'Accounts aren\'t set up for this app yet.';
          }
          return 'Something went wrong on our side. Try again later.';
        default:
          // Not shown raw: Firebase messages can be long and technical.
          debugPrint('Unhandled auth error ${error.code}: ${error.message}');
          return 'Something went wrong. Try again.';
      }
    }
    return 'Something went wrong. Try again.';
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}
