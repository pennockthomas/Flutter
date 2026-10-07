// Which houses you are in, your invitations, and which view is selected.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/friends_service.dart';
import 'package:flut/house_models.dart';
import 'package:flut/houses_controller.dart';
import 'package:flut/houses_service.dart';

import 'fake_friends_backend.dart';
import 'fake_houses_backend.dart';

House _house(String id, List<String> members, {String name = 'House'}) =>
    House(id: id, name: name, memberUids: members, createdBy: members.first);

Future<void> _until(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late FakeHousesBackend backend;
  late StreamController<String?> uids;
  late HousesController controller;

  HousesController make() => HousesController(
    service: HousesService(backend),
    friends: FriendsService(FakeFriendsBackend()),
  );

  Future<void> signIn(String uid) async {
    uids.add(uid);
    await _until(() => controller.housesLoaded, reason: 'houses to load');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = FakeHousesBackend();
    uids = StreamController<String?>.broadcast();
    controller = make();
    await controller.start(uids: uids.stream);
  });

  tearDown(() async {
    await controller.stopForTest();
    await uids.close();
  });

  test('signed out there is nothing to show', () {
    expect(controller.isSignedIn, isFalse);
    expect(controller.houses, isEmpty);
    expect(controller.selectedHouse, isNull);
  });

  test('signing in loads your houses and invitations', () async {
    backend.addHouse(_house('h1', ['me', 'anna'], name: 'Our place'));
    backend.addHouse(_house('h2', ['anna']));
    backend.addInvite(
      const HouseInvite(
        houseId: 'h2',
        houseName: 'House',
        from: 'anna',
        fromName: 'Anna',
        to: 'me',
      ),
    );

    await signIn('me');
    await _until(() => controller.invites.isNotEmpty, reason: 'invitations');

    expect(controller.houses.map((h) => h.name), ['Our place']);
    expect(controller.invites.single.houseId, 'h2');
  });

  test('creating a house names it House and opens it', () async {
    await signIn('me');

    final house = await controller.createAndSelect();
    await _until(() => controller.selectedHouse != null, reason: 'selection');

    expect(house.name, 'House');
    expect(controller.selectedHouse!.id, house.id);
  });

  test('you can be in at most five houses', () async {
    for (var i = 0; i < HousesService.maxHouses; i++) {
      backend.addHouse(_house('h$i', ['me']));
    }
    await signIn('me');
    await _until(
      () => controller.houses.length == HousesService.maxHouses,
      reason: 'five houses',
    );

    await expectLater(
      controller.createAndSelect(),
      throwsA(
        isA<HouseException>().having(
          (e) => e.problem,
          'problem',
          HouseProblem.tooManyHouses,
        ),
      ),
    );
  });

  test('the chosen view is remembered across launches', () async {
    backend.addHouse(_house('h1', ['me']));
    await signIn('me');
    await _until(() => controller.houses.isNotEmpty, reason: 'house');
    await controller.select('h1');

    final again = make();
    final moreUids = StreamController<String?>.broadcast();
    await again.start(uids: moreUids.stream);
    moreUids.add('me');
    await _until(() => again.selectedHouse != null, reason: 'restored view');

    expect(again.selectedHouse!.id, 'h1');
    await again.stopForTest();
    await moreUids.close();
  });

  test('a house that disappears falls back to Personal', () async {
    backend.addHouse(_house('h1', ['me', 'anna']));
    await signIn('me');
    await _until(() => controller.houses.isNotEmpty, reason: 'house');
    await controller.select('h1');
    expect(controller.selectedHouse, isNotNull);

    // Someone removes you.
    backend.houses['h1'] = _house('h1', ['anna']);
    backend.addHouse(backend.houses['h1']!);
    await _until(() => controller.houses.isEmpty, reason: 'house to go');

    expect(controller.selectedHouse, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HousesController.selectedHouseKey), isNull);
  });

  test('accepting an invitation joins the house and opens it', () async {
    backend.addHouse(_house('h2', ['anna']));
    const invite = HouseInvite(
      houseId: 'h2',
      houseName: 'House',
      from: 'anna',
      fromName: 'Anna',
      to: 'me',
    );
    backend.addInvite(invite);
    await signIn('me');

    await controller.accept(invite);
    await _until(() => controller.selectedHouse != null, reason: 'joined');

    expect(controller.selectedHouse!.hasMember('me'), isTrue);
    expect(backend.invites, isEmpty);
  });

  test('declining an invitation just removes it', () async {
    backend.addHouse(_house('h2', ['anna']));
    const invite = HouseInvite(
      houseId: 'h2',
      houseName: 'House',
      from: 'anna',
      fromName: 'Anna',
      to: 'me',
    );
    backend.addInvite(invite);
    await signIn('me');

    await controller.decline(invite);

    expect(backend.invites, isEmpty);
    expect(backend.houses['h2']!.memberUids, ['anna']);
  });

  test('leaving the open house goes back to Personal', () async {
    backend.addHouse(_house('h1', ['me', 'anna']));
    await signIn('me');
    await _until(() => controller.houses.isNotEmpty, reason: 'house');
    await controller.select('h1');

    await controller.leave(controller.selectedHouse!);
    await _until(() => controller.houses.isEmpty, reason: 'left');

    expect(controller.selectedHouse, isNull);
  });

  test('signing out hides the house', () async {
    backend.addHouse(_house('h1', ['me']));
    await signIn('me');
    await _until(() => controller.houses.isNotEmpty, reason: 'house');
    await controller.select('h1');

    uids.add(null);
    await _until(() => !controller.isSignedIn, reason: 'sign-out');

    expect(controller.selectedHouse, isNull);
    expect(controller.houses, isEmpty);
  });
}
