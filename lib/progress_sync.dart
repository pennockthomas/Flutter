import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_user.dart';
import 'auth_service.dart';
import 'challenge_store.dart';
import 'progress_summary.dart';

/// Mirrors a summary of the local progress up to Firestore while signed in
/// (Phase 3b). The local JSON file stays the source of truth — this is a
/// one-way copy for friends to read, never read back into the app.
///
/// Writes are debounced so checking off several items quickly produces one
/// write, and skipped entirely when the summary hasn't actually changed.
class ProgressSync {
  ProgressSync._();

  static final ProgressSync instance = ProgressSync._();

  static const Duration _debounce = Duration(seconds: 2);

  StreamSubscription<User?>? _authSubscription;
  Timer? _pendingUpload;
  String? _lastUploaded;

  /// Call once, after `Firebase.initializeApp()` has succeeded.
  void start() {
    if (_authSubscription != null) return;
    ChallengeStore.instance.addListener(_scheduleUpload);
    // A new name is uploaded too, not just new progress.
    AppUser.listenable.addListener(_scheduleUpload);
    _authSubscription = AuthService.instance.authStateChanges.listen((user) {
      // A different (or no) account means the last upload no longer applies.
      _lastUploaded = null;
      if (user != null) _scheduleUpload(immediate: true);
    });
  }

  void _scheduleUpload({bool immediate = false}) {
    if (AuthService.instance.currentUser == null) return;
    _pendingUpload?.cancel();
    _pendingUpload = Timer(immediate ? Duration.zero : _debounce, _upload);
  }

  Future<void> _upload() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    final challenges = await ChallengeStore.instance.ensureLoaded();
    final summary = buildProgressSummary(challenges);
    final displayName = AppUser.hasName
        ? AppUser.name
        : (user.displayName?.isNotEmpty ?? false)
        ? user.displayName!
        : 'EcoSteps friend';
    final encoded = jsonEncode({'summary': summary, 'name': displayName});
    if (encoded == _lastUploaded) return;

    final firestore = FirebaseFirestore.instance;
    final userDoc = firestore.collection('users').doc(user.uid);
    try {
      final batch = firestore.batch()
        ..set(userDoc, {
          'displayName': displayName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        ..set(userDoc.collection('progress').doc('summary'), {
          ...summary,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      // Offline, Firestore queues this and completes it once reconnected.
      await batch.commit();
      _lastUploaded = encoded;
    } catch (e) {
      debugPrint('Progress sync failed: $e');
    }
  }
}
