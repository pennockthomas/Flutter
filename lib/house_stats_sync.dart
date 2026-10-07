import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_user.dart';
import 'auth_service.dart';
import 'challenge_store.dart';
import 'house_models.dart';
import 'house_stats.dart';
import 'houses_backend.dart';
import 'houses_firestore.dart';

/// Keeps your numbers up to date in every house you're in: your totals and
/// how many swaps you ticked each day (counts only, never which swaps).
/// Runs while signed in; republishes after a change, a new house, or a new
/// name, and skips writes where nothing changed.
class HouseStatsSync {
  HouseStatsSync({
    HousesBackend? backend,
    ChallengeStore? store,
    this.debounce = const Duration(seconds: 2),
    this.retryDelay = const Duration(seconds: 30),
  }) : _backend = backend ?? FirestoreHousesBackend(),
       _store = store ?? ChallengeStore.instance;

  static final HouseStatsSync instance = HouseStatsSync();

  final HousesBackend _backend;
  final ChallengeStore _store;
  final Duration debounce;
  final Duration retryDelay;

  StreamSubscription<String?>? _uidSubscription;
  StreamSubscription<List<House>>? _housesSubscription;
  Timer? _timer;
  String? _uid;
  List<House> _houses = const [];
  final Map<String, String> _lastPublished = {};
  bool _started = false;

  /// Call once, after `Firebase.initializeApp()` succeeded. [uids] is for
  /// tests; by default it follows the signed-in account.
  void start({Stream<String?>? uids}) {
    if (_started) return;
    _started = true;
    _store.addListener(_schedule);
    AppUser.listenable.addListener(_schedule);
    _uidSubscription =
        (uids ?? AuthService.instance.authStateChanges.map((user) => user?.uid))
            .listen(_onUid);
  }

  @visibleForTesting
  Future<void> dispose() async {
    _timer?.cancel();
    _store.removeListener(_schedule);
    AppUser.listenable.removeListener(_schedule);
    await _housesSubscription?.cancel();
    await _uidSubscription?.cancel();
    _started = false;
    _uid = null;
  }

  Future<void> _onUid(String? uid) async {
    await _housesSubscription?.cancel();
    _housesSubscription = null;
    _timer?.cancel();
    _uid = uid;
    _houses = const [];
    _lastPublished.clear();
    if (uid == null) return;
    _housesSubscription = _backend.watchHouses(uid).listen((houses) {
      _houses = houses;
      _schedule();
    }, onError: (Object e) => debugPrint('House watch failed: $e'));
  }

  void _schedule() {
    if (_uid == null || _houses.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(debounce, publishNow);
  }

  /// The numbers to share, from the local data.
  Future<HouseMember> currentStats(String uid) async {
    final challenges = await _store.ensureLoaded();
    return HouseMember(
      uid: uid,
      name: AppUser.hasName ? AppUser.name : 'EcoSteps friend',
      completed: _store.completedItems,
      total: _store.totalItems,
      days: dailyCounts(challenges),
    );
  }

  Future<void> publishNow() async {
    final uid = _uid;
    if (uid == null || _houses.isEmpty) return;
    try {
      final stats = await currentStats(uid);
      final encoded = jsonEncode(stats.toData());
      for (final house in _houses) {
        if (_lastPublished[house.id] == encoded) continue;
        await _backend.publishStats(house.id, uid, stats);
        _lastPublished[house.id] = encoded;
      }
    } catch (e) {
      debugPrint('Publishing house stats failed: $e');
      // Try again later, on the next change.
      _timer?.cancel();
      _timer = Timer(retryDelay, publishNow);
    }
  }
}
