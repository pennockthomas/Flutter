import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_user.dart';
import 'auth_service.dart';
import 'house_models.dart';
import 'houses_backend.dart';
import 'houses_firestore.dart';

/// Shares your name with each house you're in, so the others see it next to
/// your swaps. Runs while signed in; writes again after a new house or a new
/// name, and skips houses that already have the current name.
class HouseNameSync {
  HouseNameSync({
    HousesBackend? backend,
    this.debounce = const Duration(seconds: 1),
    this.retryDelay = const Duration(seconds: 30),
  }) : _backend = backend ?? FirestoreHousesBackend();

  static final HouseNameSync instance = HouseNameSync();

  final HousesBackend _backend;
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
    AppUser.listenable.addListener(_schedule);
    _uidSubscription =
        (uids ?? AuthService.instance.authStateChanges.map((user) => user?.uid))
            .listen(_onUid);
  }

  @visibleForTesting
  Future<void> stopForTest() async {
    _timer?.cancel();
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

  Future<void> publishNow() async {
    final uid = _uid;
    if (uid == null || _houses.isEmpty) return;
    final name = AppUser.hasName ? AppUser.name : 'EcoSteps friend';
    try {
      for (final house in _houses) {
        if (_lastPublished[house.id] == name) continue;
        await _backend.publishName(house.id, uid, name);
        _lastPublished[house.id] = name;
      }
    } catch (e) {
      debugPrint('Publishing the house name failed: $e');
      _timer?.cancel();
      _timer = Timer(retryDelay, publishNow);
    }
  }
}
