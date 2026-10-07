import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'challenge_model.dart';
import 'challenge_repository.dart';
import 'challenge_store.dart';
import 'friends_firestore.dart';
import 'friends_service.dart';
import 'house_models.dart';
import 'house_store.dart';
import 'houses_firestore.dart';
import 'houses_service.dart';
import 'progress_store.dart';

/// Which houses you are in, which invitations are waiting for you, and which
/// view the tree screen shows: "Personal" (the tree) or one of your houses.
/// The dropdown on the tree screen and the house page both read from this.
class HousesController extends ChangeNotifier {
  HousesController({
    HousesService? service,
    FriendsService? friends,
    ProgressStore? personal,
    Future<Map<String, Challenge>> Function()? loadCatalog,
  }) : service = service ?? HousesService(FirestoreHousesBackend()),
       friends = friends ?? FriendsService(FirestoreFriendsBackend()),
       _personal = personal ?? ChallengeStore.instance,
       _loadCatalog = loadCatalog ?? ChallengeRepository().loadBundledCatalog;

  static final HousesController instance = HousesController();

  /// Preference holding the id of the house that was open last.
  static const String selectedHouseKey = 'scope.house_id';

  final HousesService service;
  final FriendsService friends;
  final ProgressStore _personal;
  final Future<Map<String, Challenge>> Function() _loadCatalog;

  HouseStore? _houseStore;

  /// Told when a change to the open house's tree was refused by the cloud
  /// (after it had already been shown).
  void Function(Object error)? onHouseWriteFailed;

  /// The swaps and branches the tree screen works with: yours, or the open
  /// house's shared tree.
  ProgressStore get activeStore => _houseStore ?? _personal;

  /// The shared tree of the open house, or null in Personal.
  HouseStore? get houseStore => _houseStore;

  StreamSubscription<String?>? _uidSubscription;
  StreamSubscription<List<House>>? _housesSubscription;
  StreamSubscription<List<HouseInvite>>? _invitesSubscription;

  String? _uid;
  List<House> _houses = const [];
  List<HouseInvite> _invites = const [];
  bool _housesLoaded = false;
  String? _selectedId;
  bool _started = false;

  String? get uid => _uid;
  bool get isSignedIn => _uid != null;
  List<House> get houses => _houses;
  List<HouseInvite> get invites => _invites;

  /// Whether the list of houses has arrived yet (it may be empty).
  bool get housesLoaded => _housesLoaded;

  /// The house being shown, or null for "Personal".
  House? get selectedHouse {
    final id = _selectedId;
    if (id == null || _uid == null) return null;
    for (final house in _houses) {
      if (house.id == id) return house;
    }
    return null;
  }

  /// Call once at startup. [uids] is for tests; by default it follows the
  /// signed-in account. Does nothing useful without Firebase: the dropdown
  /// then only offers Personal.
  Future<void> start({Stream<String?>? uids}) async {
    if (_started) return;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedId = prefs.getString(selectedHouseKey);
    } catch (e) {
      debugPrint('Could not read the last house: $e');
    }
    _uidSubscription =
        (uids ?? AuthService.instance.authStateChanges.map((user) => user?.uid))
            .listen(_onUid);
  }

  @visibleForTesting
  Future<void> stopForTest() async {
    await _uidSubscription?.cancel();
    await _housesSubscription?.cancel();
    await _invitesSubscription?.cancel();
    await _houseStore?.close();
    _houseStore = null;
    _started = false;
  }

  /// Makes [activeStore] match the open house: a shared tree for it, or
  /// none (Personal). Call before notifying listeners.
  void _refreshStore() {
    final house = selectedHouse;
    if (house == null) {
      final old = _houseStore;
      _houseStore = null;
      old?.close();
      return;
    }
    if (_houseStore?.houseId == house.id && _houseStore?.uid == _uid) return;
    final old = _houseStore;
    _houseStore = HouseStore(
      houseId: house.id,
      uid: _uid!,
      backend: service.backend,
      loadCatalog: _loadCatalog,
    )..onWriteFailed = (error) => onHouseWriteFailed?.call(error);
    _houseStore!.start();
    old?.close();
  }

  void _notify() {
    _refreshStore();
    notifyListeners();
  }

  Future<void> _onUid(String? uid) async {
    await _housesSubscription?.cancel();
    await _invitesSubscription?.cancel();
    _housesSubscription = null;
    _invitesSubscription = null;
    _uid = uid;
    _houses = const [];
    _invites = const [];
    _housesLoaded = false;
    _notify();
    if (uid == null) return;

    _housesSubscription = service.watchHouses(uid).listen((houses) {
      _houses = houses;
      _housesLoaded = true;
      // A house you left (or were removed from) can't stay selected.
      if (_selectedId != null && !houses.any((h) => h.id == _selectedId)) {
        _selectedId = null;
        _saveSelection();
      }
      _notify();
    }, onError: (Object e) => debugPrint('Houses watch failed: $e'));
    _invitesSubscription = service.watchMyInvites(uid).listen((invites) {
      _invites = invites;
      notifyListeners();
    }, onError: (Object e) => debugPrint('Invites watch failed: $e'));
  }

  Future<void> _saveSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _selectedId;
      if (id == null) {
        await prefs.remove(selectedHouseKey);
      } else {
        await prefs.setString(selectedHouseKey, id);
      }
    } catch (e) {
      debugPrint('Could not save the selected house: $e');
    }
  }

  /// Shows [houseId], or "Personal" for null.
  Future<void> select(String? houseId) async {
    if (_selectedId == houseId) return;
    _selectedId = houseId;
    _notify();
    await _saveSelection();
  }

  /// A new house called "House", opened straight away.
  Future<House> createAndSelect() async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    if (_houses.length >= HousesService.maxHouses) {
      throw const HouseException(HouseProblem.tooManyHouses);
    }
    final house = await service.createHouse(uid);
    await select(house.id);
    return house;
  }

  Future<void> accept(HouseInvite invite) async {
    final uid = _uid;
    if (uid == null) return;
    if (_houses.length >= HousesService.maxHouses) {
      throw const HouseException(HouseProblem.tooManyHouses);
    }
    await service.accept(invite, uid);
    await select(invite.houseId);
  }

  Future<void> decline(HouseInvite invite) => service.dropInvite(invite);

  Future<void> leave(House house) async {
    final uid = _uid;
    if (uid == null) return;
    await service.leave(house, uid);
    if (_selectedId == house.id) await select(null);
  }
}
