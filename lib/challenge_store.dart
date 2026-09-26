import 'package:flutter/foundation.dart';

import 'challenge_model.dart';
import 'challenge_repository.dart';

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
    if (!_isLoaded) {
      await reload();
    }
    return _challenges;
  }

  Future<Map<String, Challenge>> reload() async {
    _challenges = await _repository.loadChallenges();
    _isLoaded = true;
    notifyListeners();
    return _challenges;
  }

  Future<void> save(Map<String, Challenge> challenges) async {
    _challenges = Map<String, Challenge>.from(challenges);
    _isLoaded = true;
    await _repository.saveChallenges(_challenges.values);
    notifyListeners();
  }
}
