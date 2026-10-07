// What gets shared into each house you are in, and when: your totals and the
// swaps you ticked per day (counts only), kept up to date while signed in.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/app_user.dart';
import 'package:flut/challenge_store.dart';
import 'package:flut/house_models.dart';
import 'package:flut/house_stats.dart';
import 'package:flut/house_stats_sync.dart';

import 'fake_houses_backend.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = ChallengeStore.instance;
  late Directory tempDir;
  late FakeHousesBackend backend;
  late StreamController<String?> uids;
  late HouseStatsSync sync;

  House house(String id, List<String> members) => House(
    id: id,
    name: 'House',
    memberUids: members,
    createdBy: members.first,
  );

  Future<void> tick(String id, bool done) async {
    await store.save({
      for (final entry in store.challenges.entries)
        entry.key: entry.value.copyWith(
          checklist: [
            for (final item in entry.value.checklist)
              item.id == id ? item.copyWith(isCompleted: done) : item,
          ],
        ),
    });
  }

  HouseMember? mine(String houseId) => backend.stats[houseId]?['me'];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('house_stats_sync_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await store.reload();
    await AppUser.setName('Me Myself');
    backend = FakeHousesBackend();
    uids = StreamController<String?>();
    sync = HouseStatsSync(
      backend: backend,
      debounce: const Duration(milliseconds: 10),
      retryDelay: const Duration(milliseconds: 30),
    )..start(uids: uids.stream);
  });

  tearDown(() async {
    await sync.dispose();
    await uids.close();
    tempDir.deleteSync(recursive: true);
  });

  test('on sign-in it shares your totals and name in every house', () async {
    backend.addHouse(house('h1', ['me']));
    backend.addHouse(house('h2', ['me', 'anna']));
    await tick('kitchen.metal-knives', true);

    uids.add('me');
    await _until(
      () => mine('h1') != null && mine('h2') != null,
      reason: 'both houses to get my numbers',
    );

    expect(mine('h1')!.name, 'Me Myself');
    expect(mine('h1')!.completed, 1);
    expect(mine('h1')!.total, store.totalItems);
    expect(mine('h2')!.completed, 1);
  });

  test('what is shared has counts per day and no swap names', () async {
    backend.addHouse(house('h1', ['me']));
    await tick('kitchen.metal-knives', true);
    await tick('kitchen.wooden-spoons', true);

    uids.add('me');
    await _until(() => mine('h1') != null, reason: 'numbers to arrive');

    expect(mine('h1')!.days, {dayKey(DateTime.now()): 2});
    final data = mine('h1')!.toData().toString().toLowerCase();
    expect(data, isNot(contains('knives')));
    expect(data, isNot(contains('spoons')));
  });

  test('a new tick is shared; unchanged data is not written again', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => mine('h1') != null, reason: 'first publish');
    final writes = backend.publishCount;

    await tick('kitchen.metal-knives', true);
    await _until(() => mine('h1')!.completed == 1, reason: 'the tick');
    expect(backend.publishCount, writes + 1);

    // Saving without changing anything does not write again.
    await store.save(store.challenges);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(backend.publishCount, writes + 1);
  });

  test('a new name is shared', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => mine('h1') != null, reason: 'first publish');

    await AppUser.setName('Mila Vermeer');

    await _until(() => mine('h1')!.name == 'Mila Vermeer', reason: 'the name');
  });

  test('joining another house shares your numbers there too', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => mine('h1') != null, reason: 'first publish');

    backend.addHouse(house('h2', ['anna', 'me']));

    await _until(() => mine('h2') != null, reason: 'the new house');
  });

  test('signing out stops sharing', () async {
    backend.addHouse(house('h1', ['me']));
    uids.add('me');
    await _until(() => mine('h1') != null, reason: 'first publish');

    uids.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final writes = backend.publishCount;
    await tick('kitchen.metal-knives', true);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(backend.publishCount, writes);
  });

  test('a failed write is retried', () async {
    backend.failPublishTimes = 2;
    backend.addHouse(house('h1', ['me']));

    uids.add('me');

    await _until(() => mine('h1') != null, reason: 'the retry to succeed');
  });

  test('being in no house shares nothing', () async {
    uids.add('me');
    await tick('kitchen.metal-knives', true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(backend.publishCount, 0);
  });
}
