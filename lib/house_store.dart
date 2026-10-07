import 'dart:async';

import 'package:flutter/foundation.dart';

import 'challenge_model.dart';
import 'house_models.dart';
import 'houses_backend.dart';
import 'progress_store.dart';

/// A house's shared tree: the same swaps and branches as everyone's, but the
/// ticks and open branches belong to the house, so a swap ticked by one
/// member is ticked for all of them. Each tick records who made it and when
/// (that's what the house's ranking and graph are built from).
///
/// Changes show on screen at once and are sent to the cloud in the
/// background; if a send fails the change is taken back and
/// [onWriteFailed] is told.
class HouseStore extends ChangeNotifier implements ProgressStore {
  HouseStore({
    required this.houseId,
    required this.uid,
    required HousesBackend backend,
    required Future<Map<String, Challenge>> Function() loadCatalog,
    int Function()? clock,
    this.loadTimeout = const Duration(seconds: 4),
  }) : _backend = backend,
       _loadCatalog = loadCatalog,
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String houseId;
  final String uid;
  final HousesBackend _backend;
  final Future<Map<String, Challenge>> Function() _loadCatalog;
  final int Function() _clock;
  final Duration loadTimeout;

  /// Called (once per failed change) when the cloud refused a change that had
  /// already been shown.
  void Function(Object error)? onWriteFailed;

  Map<String, Challenge> _catalog = const {};
  final Map<String, HouseSwap> _swaps = {};
  final Map<String, HouseTier> _tiers = {};
  Map<String, Challenge>? _view;

  bool _catalogLoaded = false;
  bool _haveSwaps = false;
  bool _haveTiers = false;
  final Completer<void> _ready = Completer<void>();
  StreamSubscription<List<HouseSwap>>? _swapSubscription;
  StreamSubscription<List<HouseTier>>? _tierSubscription;
  bool _disposed = false;

  @override
  bool get isPersonal => false;

  /// Starts loading the swap list and listening to the house. Call once.
  void start() {
    _loadCatalog().then((catalog) {
      _catalog = catalog;
      _catalogLoaded = true;
      _changed();
      _checkReady();
    });
    _swapSubscription = _backend.watchSwaps(houseId).listen((swaps) {
      _swaps
        ..clear()
        ..addEntries(swaps.map((s) => MapEntry(s.id, s)));
      _haveSwaps = true;
      _changed();
      _checkReady();
    }, onError: (Object e) => debugPrint('House swaps failed: $e'));
    _tierSubscription = _backend.watchTiers(houseId).listen((tiers) {
      _tiers
        ..clear()
        ..addEntries(tiers.map((t) => MapEntry(t.label, t)));
      _haveTiers = true;
      _changed();
      _checkReady();
    }, onError: (Object e) => debugPrint('House tiers failed: $e'));
  }

  void _checkReady() {
    if (_catalogLoaded && _haveSwaps && _haveTiers && !_ready.isCompleted) {
      _ready.complete();
    }
  }

  void _changed() {
    _view = null;
    if (!_disposed) notifyListeners();
  }

  @override
  Map<String, Challenge> get challenges => _view ??= _buildView();

  Map<String, Challenge> _buildView() {
    return {
      for (final entry in _catalog.entries)
        entry.key: entry.value.copyWith(
          checklist: [
            for (final item in entry.value.checklist)
              item.copyWith(
                isCompleted: _swaps[item.id]?.done ?? false,
                updatedAt: _swaps[item.id]?.at,
              ),
          ],
        ),
    };
  }

  int get totalItems => _catalog.values.fold(
    0,
    (total, challenge) => total + challenge.checklist.length,
  );

  /// Swaps that are ticked in the house right now.
  int get completedItems => challenges.values.fold(
    0,
    (total, challenge) =>
        total + challenge.checklist.where((i) => i.isCompleted).length,
  );

  @override
  Future<Map<String, Challenge>> ensureLoaded() async {
    // Offline the first answer can take a while; show the tree anyway.
    await _ready.future.timeout(loadTimeout, onTimeout: () {});
    return challenges;
  }

  @override
  Set<String> get unlockedTiers => {
    for (final tier in _tiers.values)
      if (tier.open) tier.label,
  };

  @override
  Future<void> save(Map<String, Challenge> incoming) async {
    final current = {
      for (final challenge in challenges.values)
        for (final item in challenge.checklist) item.id: item,
    };
    final now = _clock();
    final changed = <HouseSwap>[];
    for (final challenge in incoming.values) {
      for (final item in challenge.checklist) {
        final before = current[item.id];
        // Only swaps that are in the house's tree can be ticked.
        if (before == null || before.isCompleted == item.isCompleted) continue;
        changed.add(
          HouseSwap(id: item.id, done: item.isCompleted, at: now, by: uid),
        );
      }
    }
    if (changed.isEmpty) return;

    final previous = {for (final swap in changed) swap.id: _swaps[swap.id]};
    for (final swap in changed) {
      _swaps[swap.id] = swap;
    }
    _changed();

    unawaited(
      _backend.writeSwaps(houseId, changed).catchError((Object error) {
        for (final swap in changed) {
          final old = previous[swap.id];
          if (old == null) {
            _swaps.remove(swap.id);
          } else {
            _swaps[swap.id] = old;
          }
        }
        _changed();
        onWriteFailed?.call(error);
      }),
    );
  }

  @override
  Future<void> setTierUnlocked(String label, bool unlocked) async {
    if (_tiers[label]?.open == unlocked) return;
    final previous = _tiers[label];
    final tier = HouseTier(label: label, open: unlocked, at: _clock(), by: uid);
    _tiers[label] = tier;
    _changed();
    unawaited(
      _backend.writeTier(houseId, tier).catchError((Object error) {
        if (previous == null) {
          _tiers.remove(label);
        } else {
          _tiers[label] = previous;
        }
        _changed();
        onWriteFailed?.call(error);
      }),
    );
  }

  @override
  Future<void> lockAllTiers() async {
    throw UnsupportedError('A house tree cannot be reset.');
  }

  /// Stops listening. The store can't be used afterwards.
  Future<void> close() async {
    _disposed = true;
    await _swapSubscription?.cancel();
    await _tierSubscription?.cancel();
    super.dispose();
  }
}
