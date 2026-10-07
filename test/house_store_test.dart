// A house's shared tree: ticks belong to the house, record who made them,
// show at once, and are taken back if the cloud refuses them.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/house_models.dart';
import 'package:flut/house_store.dart';

import 'fake_houses_backend.dart';

Map<String, Challenge> _catalog() => {
  'Start': const Challenge(
    label: 'Start',
    description: '',
    unlocks: ['Kitchen'],
  ),
  'Kitchen': const Challenge(
    label: 'Kitchen',
    description: '',
    unlocks: [],
    checklist: [
      ChecklistItem(id: 'k.knives', label: 'Metal knives'),
      ChecklistItem(id: 'k.spoons', label: 'Wooden spoons'),
      ChecklistItem(id: 'k.pan', label: 'Cast iron pan'),
    ],
  ),
};

class _SilentBackend extends FakeHousesBackend {
  @override
  Stream<List<HouseSwap>> watchSwaps(String houseId) =>
      StreamController<List<HouseSwap>>().stream;
}

Map<String, Challenge> _withDone(
  Map<String, Challenge> challenges,
  Set<String> done,
) => {
  for (final entry in challenges.entries)
    entry.key: entry.value.copyWith(
      checklist: [
        for (final item in entry.value.checklist)
          item.copyWith(isCompleted: done.contains(item.id)),
      ],
    ),
};

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
  late HouseStore store;
  var clock = 1000;

  HouseStore make({FakeHousesBackend? using, String uid = 'me'}) => HouseStore(
    houseId: 'h1',
    uid: uid,
    backend: using ?? backend,
    loadCatalog: () async => _catalog(),
    clock: () => clock,
    loadTimeout: const Duration(milliseconds: 100),
  )..start();

  bool done(HouseStore s, String id) => s.challenges.values
      .expand((c) => c.checklist)
      .firstWhere((i) => i.id == id)
      .isCompleted;

  setUp(() async {
    clock = 1000;
    backend = FakeHousesBackend();
    store = make();
    await store.ensureLoaded();
  });

  tearDown(() async => store.close());

  test(
    'it is the swap list with nothing ticked, and it is not personal',
    () async {
      expect(store.isPersonal, isFalse);
      expect(store.challenges.keys, ['Start', 'Kitchen']);
      expect(store.totalItems, 3);
      expect(store.completedItems, 0);
      expect(store.unlockedTiers, isEmpty);
    },
  );

  test('swaps ticked in the house show as ticked, with when', () async {
    backend.swaps['h1'] = {
      'k.knives': const HouseSwap(
        id: 'k.knives',
        done: true,
        at: 500,
        by: 'anna',
      ),
      'k.pan': const HouseSwap(id: 'k.pan', done: false, at: 600, by: 'anna'),
    };
    final fresh = make();
    await fresh.ensureLoaded();

    expect(done(fresh, 'k.knives'), isTrue);
    expect(done(fresh, 'k.pan'), isFalse);
    expect(fresh.completedItems, 1);
    await fresh.close();
  });

  test('ticking a swap saves who ticked it and when', () async {
    clock = 2500;

    await store.save(_withDone(store.challenges, {'k.spoons'}));
    await _until(() => backend.swaps['h1'] != null, reason: 'the write');

    final saved = backend.swaps['h1']!['k.spoons']!;
    expect(saved.done, isTrue);
    expect(saved.by, 'me');
    expect(saved.at, 2500);
    expect(backend.swaps['h1']!.length, 1, reason: 'only what changed');
  });

  test('the tick shows at once, before the cloud has answered', () async {
    var notified = 0;
    store.addListener(() => notified++);

    await store.save(_withDone(store.challenges, {'k.knives'}));

    expect(done(store, 'k.knives'), isTrue);
    expect(notified, greaterThan(0));
  });

  test('unticking is saved too, by whoever did it', () async {
    backend.swaps['h1'] = {
      'k.knives': const HouseSwap(
        id: 'k.knives',
        done: true,
        at: 500,
        by: 'anna',
      ),
    };
    final mine = make(uid: 'me');
    await mine.ensureLoaded();
    clock = 3000;

    await mine.save(_withDone(mine.challenges, {}));
    await _until(
      () => backend.swaps['h1']!['k.knives']!.done == false,
      reason: 'the untick',
    );

    expect(backend.swaps['h1']!['k.knives']!.by, 'me');
    expect(backend.swaps['h1']!['k.knives']!.at, 3000);
    await mine.close();
  });

  test('saving without changes writes nothing', () async {
    await store.save(store.challenges);

    expect(backend.writeCount, 0);
  });

  test('swaps that are not in the house tree are ignored', () async {
    final withExtra = {
      ...store.challenges,
      'Kitchen': store.challenges['Kitchen']!.copyWith(
        checklist: [
          ...store.challenges['Kitchen']!.checklist,
          const ChecklistItem(
            id: 'mine.only',
            label: 'Mine',
            isCompleted: true,
          ),
        ],
      ),
    };

    await store.save(withExtra);

    expect(backend.writeCount, 0);
  });

  test("another member's tick appears here", () async {
    var notified = 0;
    store.addListener(() => notified++);

    backend.swaps['h1'] = {
      'k.pan': const HouseSwap(id: 'k.pan', done: true, at: 700, by: 'anna'),
    };
    backend.addHouse(
      const House(id: 'h1', name: 'House', memberUids: ['me'], createdBy: 'me'),
    );
    await _until(() => done(store, 'k.pan'), reason: "anna's tick");

    expect(notified, greaterThan(0));
  });

  test('a refused tick is shown first, then taken back and reported', () async {
    Object? reported;
    store.onWriteFailed = (e) => reported = e;
    backend.failWriteTimes = 1;
    final seen = <bool>[];
    store.addListener(() => seen.add(done(store, 'k.knives')));

    await store.save(_withDone(store.challenges, {'k.knives'}));
    await _until(() => reported != null, reason: 'the failure');

    expect(seen, [true, false]);
    expect(done(store, 'k.knives'), isFalse);
  });

  test('branches can be opened for the whole house', () async {
    clock = 4000;

    await store.setTierUnlocked('Kitchen', true);
    await _until(() => backend.tiers['h1'] != null, reason: 'the write');

    expect(store.unlockedTiers, {'Kitchen'});
    expect(backend.tiers['h1']!['Kitchen']!.by, 'me');
    expect(backend.tiers['h1']!['Kitchen']!.at, 4000);
  });

  test("a branch another member opened appears here", () async {
    backend.tiers['h1'] = {
      'Kitchen': const HouseTier(
        label: 'Kitchen',
        open: true,
        at: 1,
        by: 'anna',
      ),
    };
    backend.addHouse(
      const House(id: 'h1', name: 'House', memberUids: ['me'], createdBy: 'me'),
    );

    await _until(
      () => store.unlockedTiers.contains('Kitchen'),
      reason: 'branch',
    );
  });

  test('a refused branch is taken back', () async {
    var reported = false;
    store.onWriteFailed = (_) => reported = true;
    backend.failWriteTimes = 1;

    await store.setTierUnlocked('Kitchen', true);
    await _until(() => reported, reason: 'the failure');

    expect(store.unlockedTiers, isEmpty);
  });

  test('opening an open branch again changes nothing', () async {
    await store.setTierUnlocked('Kitchen', true);
    await _until(() => backend.tiers['h1'] != null, reason: 'first write');
    backend.tiers['h1']!.clear();

    await store.setTierUnlocked('Kitchen', true);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(backend.tiers['h1']!, isEmpty);
  });

  test('a house tree cannot be reset', () async {
    await expectLater(store.lockAllTiers(), throwsUnsupportedError);
  });

  test('if the house is slow to answer the tree still opens', () async {
    final slow = make(using: _SilentBackend());

    final challenges = await slow.ensureLoaded();

    expect(challenges.keys, ['Start', 'Kitchen']);
    await slow.close();
  });
}
