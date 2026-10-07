import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'challenge_store.dart';
import 'progress_merge.dart';
import 'progress_remote.dart';

enum SyncStatus {
  /// Nobody is signed in; progress lives only on this device.
  signedOut,

  /// Talking to the cloud.
  syncing,

  /// The last sync succeeded.
  upToDate,

  /// The last sync failed (offline, say); it will be retried.
  failed,
}

/// Keeps a signed-in account's ticked swaps in step across devices.
///
/// The local save stays the source of truth and the app works exactly the
/// same signed out. While signed in: on sign-in and after every local change
/// (debounced) this reads the cloud state, merges it swap by swap (newest
/// change wins, see `mergeProgress`) and stores the result; and a live
/// listener merges in changes other devices make. Failures (offline, say)
/// are retried with a growing delay.
///
/// Separate from `ProgressSync`, which uploads only a counts summary for
/// friends to read.
class ProgressStateSync {
  ProgressStateSync({
    ProgressRemote? remote,
    ChallengeStore? store,
    this.debounce = const Duration(seconds: 2),
    this.firstRetry = const Duration(seconds: 15),
    this.maxRetry = const Duration(minutes: 5),
  }) : _remote = remote ?? FirestoreProgressRemote(),
       _store = store ?? ChallengeStore.instance;

  static final ProgressStateSync instance = ProgressStateSync();

  /// For a sync-status indicator.
  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.signedOut);

  /// How many syncs have finished successfully (lets tests wait for one).
  @visibleForTesting
  int completedSyncs = 0;

  /// Pref remembering which account this device's progress belongs to.
  static const String lastUidKey = 'sync.last_uid';

  final ProgressRemote _remote;
  final ChallengeStore _store;
  final Duration debounce;
  final Duration firstRetry;
  final Duration maxRetry;

  StreamSubscription<String?>? _uidSubscription;
  StreamSubscription<List<ItemStamp>>? _remoteSubscription;
  Timer? _timer;
  String? _uid;
  bool _started = false;
  bool _syncing = false;
  bool _syncAgain = false;
  int _failures = 0;

  /// While we're writing the cloud's changes into the local data, the
  /// resulting store notifications aren't new local changes to upload.
  int _applying = 0;

  /// Call once, after `Firebase.initializeApp()` has succeeded. [uids] is for
  /// tests; by default it follows the signed-in account.
  void start({Stream<String?>? uids}) {
    if (_started) return;
    _started = true;
    _store.addListener(_onLocalChange);
    _uidSubscription =
        (uids ?? AuthService.instance.authStateChanges.map((user) => user?.uid))
            .listen(_onUid);
  }

  @visibleForTesting
  Future<void> dispose() async {
    _timer?.cancel();
    _store.removeListener(_onLocalChange);
    await _remoteSubscription?.cancel();
    await _uidSubscription?.cancel();
    _started = false;
    _uid = null;
  }

  Future<void> _onUid(String? uid) async {
    await _remoteSubscription?.cancel();
    _remoteSubscription = null;
    _timer?.cancel();
    _uid = uid;
    _failures = 0;
    if (uid == null) {
      // Signed out: keep the local progress as it is.
      status.value = SyncStatus.signedOut;
      return;
    }
    status.value = SyncStatus.syncing;

    // A different account than last time: this device's swaps belong to the
    // previous one (safe in its cloud copy), so start from nothing instead
    // of mixing two people's progress.
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(lastUidKey);
    if (last != null && last != uid) await _store.clearProgress();
    await prefs.setString(lastUidKey, uid);
    if (_uid != uid) return; // signed out or switched while we were busy

    _remoteSubscription = _remote
        .watch(uid)
        .listen(
          _onRemote,
          onError: (e) {
            debugPrint('Progress watch failed: $e');
          },
        );
    await syncNow();
  }

  void _onLocalChange() {
    if (_applying > 0 || _uid == null) return;
    _schedule(debounce);
  }

  Future<void> _onRemote(List<ItemStamp> state) async {
    final uid = _uid;
    if (uid == null) return;
    _applying++;
    try {
      final result = await _store.mergeRemote(state);
      if (result.remoteChanged) _schedule(debounce);
    } catch (e) {
      debugPrint('Progress merge failed: $e');
    } finally {
      _applying--;
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, syncNow);
  }

  /// Merges with the cloud now. Overlapping calls collapse into one more run.
  Future<void> syncNow() async {
    final uid = _uid;
    if (uid == null) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    status.value = SyncStatus.syncing;
    try {
      do {
        _syncAgain = false;
        await _store.ensureLoaded();
        _applying++;
        try {
          await _remote.exchange(uid, (remote) => _store.mergeRemote(remote));
        } finally {
          _applying--;
        }
      } while (_syncAgain && _uid == uid);
      _failures = 0;
      if (_uid == uid) status.value = SyncStatus.upToDate;
      completedSyncs++;
    } catch (e) {
      debugPrint('Progress sync failed: $e');
      if (_uid == uid) status.value = SyncStatus.failed;
      _failures++;
      final delay = firstRetry * (1 << (_failures - 1).clamp(0, 10));
      _schedule(delay > maxRetry ? maxRetry : delay);
    } finally {
      _syncing = false;
    }
  }
}
