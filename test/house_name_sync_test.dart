// Your name, shared into each house you are in.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';
import 'package:flut/house_models.dart';
import 'package:flut/house_name_sync.dart';

import 'fake_houses_backend.dart';

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
  late HouseNameSync sync;

  House house(String id, List<String> members) => House(
    id: id,
    name: 'House',
    memberUids: members,
    createdBy: members.first,
  );

  String? nameIn(String houseId) => backend.names[houseId]?['me'];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppUser.setName('Me Myself');
    backend = FakeHousesBackend();
    uids = StreamController<String?>();
    sync = HouseNameSync(
      backend: backend,
      debounce: const Duration(milliseconds: 10),
      retryDelay: const Duration(milliseconds: 30),
    )..start(uids: uids.stream);
  });

  tearDown(() async {
    await sync.stopForTest();
    await uids.close();
  });

  test('on sign-in your name is shared in every house', () async {
    backend.addHouse(house('h1', ['me']));
    backend.addHouse(house('h2', ['me', 'anna']));

    uids.add('me');
    await _until(
      () => nameIn('h1') != null && nameIn('h2') != null,
      reason: 'both houses to get the name',
    );

    expect(nameIn('h1'), 'Me Myself');
    expect(nameIn('h2'), 'Me Myself');
  });

  test(
    'a new name is shared, and an unchanged one is not written again',
    () async {
      backend.addHouse(house('h1', ['me']));
      uids.add('me');
      await _until(() => nameIn('h1') != null, reason: 'first publish');
      final writes = backend.publishCount;

      await AppUser.setName('Mila Vermeer');
      await _until(() => nameIn('h1') == 'Mila Vermeer', reason: 'new name');
      expect(backend.publishCount, writes + 1);

      // Nothing changed: no further write.
      backend.addHouse(house('h1', ['me']));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.publishCount, writes + 1);
    },
  );

  test('joining another house shares the name there too', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => nameIn('h1') != null, reason: 'first publish');

    backend.addHouse(house('h2', ['anna', 'me']));

    await _until(() => nameIn('h2') != null, reason: 'the new house');
  });

  test('signing out stops sharing', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => nameIn('h1') != null, reason: 'first publish');

    uids.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final writes = backend.publishCount;
    await AppUser.setName('Someone Else');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(backend.publishCount, writes);
  });

  test('a failed write is retried', () async {
    backend.failPublishTimes = 2;
    backend.addHouse(house('h1', ['me']));

    uids.add('me');

    await _until(() => nameIn('h1') != null, reason: 'the retry');
  });

  test('being in no house shares nothing', () async {
    uids.add('me');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(backend.publishCount, 0);
  });
}
