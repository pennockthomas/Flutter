import 'dart:async';

import 'package:flut/house_models.dart';
import 'package:flut/houses_backend.dart';

/// An in-memory [HousesBackend] for tests.
class FakeHousesBackend implements HousesBackend {
  final Map<String, House> houses = {};
  final Map<String, Map<String, HouseMember>> stats = {};
  final Map<String, HouseInvite> invites = {};
  final _changes = StreamController<void>.broadcast();

  int publishCount = 0;
  int failPublishTimes = 0;
  int _nextId = 1;

  void _changed() => _changes.add(null);

  void addHouse(House house) {
    houses[house.id] = house;
    _changed();
  }

  void addInvite(HouseInvite invite) {
    invites[invite.id] = invite;
    _changed();
  }

  /// A stream of the current value that updates on every change. Built on a
  /// plain controller (not `async*`), so cancelling it completes at once.
  Stream<T> _live<T>(T Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        subscription = _changes.stream.listen((_) => controller.add(read()));
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<List<House>> watchHouses(String uid) => _live(
    () => [
      for (final house in houses.values)
        if (house.hasMember(uid)) house,
    ],
  );

  @override
  Stream<List<HouseMember>> watchMemberStats(String houseId) =>
      _live(() => [...?stats[houseId]?.values]);

  @override
  Stream<List<HouseInvite>> watchMyInvites(String uid) => _live(
    () => [
      for (final invite in invites.values)
        if (invite.to == uid) invite,
    ],
  );

  @override
  Stream<List<HouseInvite>> watchHouseInvites(String houseId) => _live(
    () => [
      for (final invite in invites.values)
        if (invite.houseId == houseId) invite,
    ],
  );

  @override
  Future<House> createHouse(String uid, String name) async {
    final house = House(
      id: 'house${_nextId++}',
      name: name,
      memberUids: [uid],
      createdBy: uid,
    );
    addHouse(house);
    return house;
  }

  @override
  Future<void> renameHouse(String houseId, String name) async {
    final house = houses[houseId]!;
    addHouse(
      House(
        id: house.id,
        name: name,
        memberUids: house.memberUids,
        createdBy: house.createdBy,
      ),
    );
  }

  @override
  Future<void> sendInvite(HouseInvite invite) async => addInvite(invite);

  @override
  Future<void> acceptInvite(HouseInvite invite, String uid) async {
    final house = houses[invite.houseId]!;
    invites.remove(invite.id);
    addHouse(
      House(
        id: house.id,
        name: house.name,
        memberUids: [...house.memberUids, uid],
        createdBy: house.createdBy,
      ),
    );
  }

  @override
  Future<void> deleteInvite(HouseInvite invite) async {
    invites.remove(invite.id);
    _changed();
  }

  @override
  Future<void> removeMember(House house, String memberUid) async {
    stats[house.id]?.remove(memberUid);
    if (house.memberUids.length <= 1) {
      houses.remove(house.id);
    } else {
      houses[house.id] = House(
        id: house.id,
        name: house.name,
        memberUids: [
          for (final uid in house.memberUids)
            if (uid != memberUid) uid,
        ],
        createdBy: house.createdBy,
      );
    }
    _changed();
  }

  @override
  Future<void> publishStats(
    String houseId,
    String uid,
    HouseMember member,
  ) async {
    if (failPublishTimes > 0) {
      failPublishTimes--;
      throw StateError('offline');
    }
    publishCount++;
    (stats[houseId] ??= {})[uid] = member;
    _changed();
  }
}
