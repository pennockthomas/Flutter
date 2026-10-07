import 'package:flutter/foundation.dart';

import 'challenge_model.dart';
import 'challenge_repository.dart';
import 'progress_merge.dart';

/// Single in-memory source of truth for challenge data, shared by every
/// screen. Without this, each screen kept its own copy loaded independently,
/// so a change made in one place (e.g. checking off an item in the Progress
/// Register) wasn't reflected in another screen already on the navigation
/// stack until it happened to reload on its own.
class ChallengeStore extends ChangeNotifier {
  ChallengeStore._();

  static final ChallengeStore instance = ChallengeStore._();

  final ChallengeRepository _repository = ChallengeRepository();

  Map<String, Challenge> _challenges = {};
  bool _isLoaded = false;

  /// The first load, shared by every caller that asks before it finishes.
  Future<Map<String, Challenge>>? _initialLoad;

  /// Tail of the queue of disk operations. Loading can rewrite the save file
  /// and every write goes through the same `.tmp` file, so two overlapping
  /// operations can rename that file out from under each other (seen once
  /// the main tabs started loading at the same moment). Everything that
  /// touches disk runs one at a time through [_serialized].
  Future<void> _diskQueue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _diskQueue.then((_) => operation());
    _diskQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Map<String, Challenge> get challenges => _challenges;

  int get totalItems => _challenges.values.fold(
    0,
    (total, challenge) => total + challenge.checklist.length,
  );

  int get completedItems => _challenges.values.fold(
    0,
    (total, challenge) =>
        total + challenge.checklist.where((item) => item.isCompleted).length,
  );

  double get progress {
    final total = totalItems;
    return total == 0 ? 0 : completedItems / total;
  }

  /// Returns the current challenges, loading them from disk only the first
  /// time this is called in the app's lifetime.
  Future<Map<String, Challenge>> ensureLoaded() async {
    if (_isLoaded) return _challenges;
    final load = _initialLoad ??= reload();
    try {
      return await load;
    } finally {
      // A failed load shouldn't be cached forever; let the next call retry.
      if (!_isLoaded) _initialLoad = null;
    }
  }

  Future<Map<String, Challenge>> reload() => _serialized(_reloadNow);

  /// Only call from inside [_serialized] (or via [reload]).
  Future<Map<String, Challenge>> _reloadNow() async {
    _challenges = await _repository.loadChallenges();
    _isLoaded = true;
    notifyListeners();
    return _challenges;
  }

  /// Saves [challenges]. Items whose completion differs from what's stored
  /// are stamped with the current time (see [ChecklistItem.updatedAt]), so
  /// every screen that ticks or unticks a swap gets sync-ready timestamps
  /// without knowing about them. Pass `stamp: false` to store the data
  /// exactly as given.
  Future<void> save(Map<String, Challenge> challenges, {bool stamp = true}) {
    final incoming = Map<String, Challenge>.from(challenges);
    return _serialized(() async {
      final updatedChallenges = stamp
          ? stampChanges(
              _challenges,
              incoming,
              DateTime.now().millisecondsSinceEpoch,
            )
          : incoming;
      await _repository.saveChallenges(updatedChallenges.values);
      _challenges = updatedChallenges;
      _isLoaded = true;
      notifyListeners();
    });
  }

  /// Merges the cloud's state into the local data (see [mergeProgress]),
  /// saving and notifying only if something changed locally. Runs in the
  /// disk queue, so it sees the very latest local data. [now] is for tests.
  Future<MergeResult> mergeRemote(List<ItemStamp> remote, {int? now}) {
    return _serialized(() async {
      if (!_isLoaded) await _reloadNow();
      final result = mergeProgress(
        local: _challenges,
        remote: remote,
        now: now ?? DateTime.now().millisecondsSinceEpoch,
      );
      if (result.localChanged) {
        await _repository.saveChallenges(result.challenges.values);
        _challenges = result.challenges;
        notifyListeners();
      }
      return result;
    });
  }

  /// Unticks everything and forgets all timestamps, without stamping: the
  /// device has no progress of its own any more (used when a different
  /// account signs in, so one person's swaps never leak into another's).
  Future<void> clearProgress() {
    return _serialized(() async {
      if (!_isLoaded) await _reloadNow();
      final cleared = {
        for (final entry in _challenges.entries)
          entry.key: entry.value.copyWith(
            checklist: [
              for (final item in entry.value.checklist)
                item.copyWith(isCompleted: false, clearUpdatedAt: true),
            ],
          ),
      };
      await _repository.saveChallenges(cleared.values);
      _challenges = cleared;
      notifyListeners();
    });
  }

  /// The saved progress as JSON text, for exporting; null if nothing has
  /// been saved yet.
  Future<String?> exportJson() => _repository.exportJson();

  /// Replaces the saved data with [jsonText] if it's valid, then reloads so
  /// every screen picks up the imported data. Returns whether it succeeded.
  Future<bool> importFromJson(String jsonText) {
    return _serialized(() async {
      final succeeded = await _repository.importFromJson(jsonText);
      // _reloadNow, not reload(): we're already inside the queue, and
      // queueing behind ourselves would never run.
      if (succeeded) await _reloadNow();
      return succeeded;
    });
  }

  bool isValidImportJson(String jsonText) =>
      _repository.isValidImportJson(jsonText);

  Future<bool> hasImportBackup() => _repository.hasImportBackup();

  Future<bool> restoreImportBackup() {
    return _serialized(() async {
      final succeeded = await _repository.restoreImportBackup();
      if (succeeded) await _reloadNow();
      return succeeded;
    });
  }
}
