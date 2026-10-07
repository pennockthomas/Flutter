import 'package:flutter/foundation.dart';

import 'challenge_model.dart';

/// What the tree needs from a place that keeps swaps and unlocked branches:
/// your own data (`ChallengeStore`) or a house's shared tree (`HouseStore`).
/// The tree screen works with whichever is selected in the dropdown.
abstract class ProgressStore implements Listenable {
  /// True for your own data. A house's shared tree can't be reset by one
  /// person, and doesn't send your personal milestone notifications.
  bool get isPersonal;

  Map<String, Challenge> get challenges;

  Future<Map<String, Challenge>> ensureLoaded();

  /// Saves [challenges]; whatever differs from what's stored is the change.
  Future<void> save(Map<String, Challenge> challenges);

  /// Labels of the branches that are open.
  Set<String> get unlockedTiers;

  Future<void> setTierUnlocked(String label, bool unlocked);

  /// Closes every branch again (Reset). Only for personal data.
  Future<void> lockAllTiers();
}
