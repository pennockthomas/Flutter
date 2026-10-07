// The rules that decide whose change wins when progress is merged between
// this device and the cloud (per-account sync). Pure logic, no Firebase.

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/progress_merge.dart';

Map<String, Challenge> _catalog(List<ChecklistItem> items) => {
  'Kitchen': Challenge(
    label: 'Kitchen',
    description: '',
    unlocks: const [],
    checklist: items,
  ),
};

ChecklistItem _item(String id, {bool done = false, int? at}) =>
    ChecklistItem(id: id, label: id, isCompleted: done, updatedAt: at);

ItemStamp _stamp(String id, bool done, int at) =>
    ItemStamp(id: id, done: done, at: at);

ChecklistItem _only(MergeResult result, String id) =>
    result.challenges['Kitchen']!.checklist.firstWhere((i) => i.id == id);

void main() {
  group('stampChanges', () {
    test('stamps items whose completion changed, and only those', () {
      final before = _catalog([_item('a', at: 5), _item('b', at: 6)]);
      final after = _catalog([
        _item('a', done: true, at: 5),
        _item('b', at: 6),
      ]);

      final stamped = stampChanges(before, after, 100);

      expect(stamped['Kitchen']!.checklist[0].updatedAt, 100);
      expect(stamped['Kitchen']!.checklist[1].updatedAt, 6);
    });

    test('stamps a new item that is already ticked, not an unticked one', () {
      final before = _catalog([_item('a')]);
      final after = _catalog([_item('a'), _item('b', done: true), _item('c')]);

      final items = stampChanges(before, after, 100)['Kitchen']!.checklist;

      expect(items[1].updatedAt, 100);
      expect(items[2].updatedAt, isNull);
    });

    test('unticking is a change too', () {
      final before = _catalog([_item('a', done: true, at: 5)]);
      final after = _catalog([_item('a', done: false, at: 5)]);

      expect(
        stampChanges(before, after, 100)['Kitchen']!.checklist.single.updatedAt,
        100,
      );
    });
  });

  group('mergeProgress', () {
    test('newer remote change wins over an older local one', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: false, at: 10)]),
        remote: [_stamp('a', true, 20)],
        now: 99,
      );

      expect(_only(result, 'a').isCompleted, isTrue);
      expect(_only(result, 'a').updatedAt, 20);
      expect(result.localChanged, isTrue);
      expect(result.remoteChanged, isFalse);
    });

    test('newer local change wins and is pushed to the cloud', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true, at: 30)]),
        remote: [_stamp('a', false, 20)],
        now: 99,
      );

      expect(_only(result, 'a').isCompleted, isTrue);
      expect(result.localChanged, isFalse);
      expect(result.remote, [_stamp('a', true, 30)]);
      expect(result.remoteChanged, isTrue);
    });

    test('an untick newer than a tick is not undone', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true, at: 10)]),
        remote: [_stamp('a', false, 20)],
        now: 99,
      );

      expect(_only(result, 'a').isCompleted, isFalse);
    });

    test('changes to different swaps on two devices both survive', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true, at: 10), _item('b')]),
        remote: [_stamp('b', true, 20)],
        now: 99,
      );

      expect(_only(result, 'a').isCompleted, isTrue);
      expect(_only(result, 'b').isCompleted, isTrue);
      expect(result.remote, [_stamp('a', true, 10), _stamp('b', true, 20)]);
    });

    test('a tie goes to the tick', () {
      final localTicked = mergeProgress(
        local: _catalog([_item('a', done: true, at: 10)]),
        remote: [_stamp('a', false, 10)],
        now: 99,
      );
      final remoteTicked = mergeProgress(
        local: _catalog([_item('a', done: false, at: 10)]),
        remote: [_stamp('a', true, 10)],
        now: 99,
      );

      expect(_only(localTicked, 'a').isCompleted, isTrue);
      expect(localTicked.remote, [_stamp('a', true, 10)]);
      expect(_only(remoteTicked, 'a').isCompleted, isTrue);
    });

    test('a tick from before timestamps is stamped now and uploaded', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true)]),
        remote: const [],
        now: 77,
      );

      expect(_only(result, 'a').updatedAt, 77);
      expect(result.localChanged, isTrue);
      expect(result.remote, [_stamp('a', true, 77)]);
    });

    test('an old unstamped tick loses to a stamped remote untick', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true)]),
        remote: [_stamp('a', false, 20)],
        now: 77,
      );

      expect(_only(result, 'a').isCompleted, isFalse);
    });

    test('untouched, unticked swaps are not uploaded', () {
      final result = mergeProgress(
        local: _catalog([_item('a'), _item('b')]),
        remote: const [],
        now: 77,
      );

      expect(result.remote, isEmpty);
      expect(result.remoteChanged, isFalse);
      expect(result.localChanged, isFalse);
    });

    test('cloud entries for swaps this device does not have are kept', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        remote: [_stamp('elsewhere', true, 5)],
        now: 77,
      );

      expect(result.remote, [_stamp('elsewhere', true, 5)]);
      expect(result.remoteChanged, isFalse);
    });

    test('merging the result again changes nothing', () {
      final first = mergeProgress(
        local: _catalog([
          _item('a', done: true),
          _item('b', done: true, at: 40),
          _item('c', done: false, at: 5),
        ]),
        remote: [_stamp('b', false, 20), _stamp('c', true, 50)],
        now: 77,
      );
      final second = mergeProgress(
        local: first.challenges,
        remote: first.remote,
        now: 1000,
      );

      expect(second.localChanged, isFalse);
      expect(second.remoteChanged, isFalse);
      expect(second.remote, first.remote);
    });

    test('duplicate cloud entries resolve to the newest', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        remote: [_stamp('a', false, 5), _stamp('a', true, 9)],
        now: 77,
      );

      expect(_only(result, 'a').isCompleted, isTrue);
    });
  });

  group('tiers', () {
    ItemStamp tier(String label, bool done, int at) =>
        ItemStamp(id: label, done: done, at: at);

    test('a tier unlocked in the cloud is unlocked here', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        remote: [_stamp('tier:Kitchen', true, 20)],
        now: 99,
      );

      expect(result.tiers, {'Kitchen': tier('Kitchen', true, 20)});
      expect(result.tiersChanged, isTrue);
      expect(result.remoteChanged, isFalse);
    });

    test(
      'a tier unlocked here is uploaded, stamped now if it had no stamp',
      () {
        final result = mergeProgress(
          local: _catalog([_item('a')]),
          localTiers: {'Kitchen': tier('Kitchen', true, 0)},
          remote: const [],
          now: 77,
        );

        expect(result.tiers['Kitchen'], tier('Kitchen', true, 77));
        expect(result.tiersChanged, isTrue);
        expect(result.remote, [_stamp('tier:Kitchen', true, 77)]);
      },
    );

    test('a newer lock (a reset) beats an older unlock', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        localTiers: {'Kitchen': tier('Kitchen', true, 10)},
        remote: [_stamp('tier:Kitchen', false, 20)],
        now: 99,
      );

      expect(result.tiers['Kitchen']!.done, isFalse);
    });

    test('a newer local unlock beats an older cloud lock and is uploaded', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        localTiers: {'Kitchen': tier('Kitchen', true, 30)},
        remote: [_stamp('tier:Kitchen', false, 20)],
        now: 99,
      );

      expect(result.tiers['Kitchen']!.done, isTrue);
      expect(result.remote, [_stamp('tier:Kitchen', true, 30)]);
    });

    test('tiers and swaps merge side by side without mixing', () {
      final result = mergeProgress(
        local: _catalog([_item('a', done: true, at: 10)]),
        localTiers: {'Kitchen': tier('Kitchen', true, 10)},
        remote: [_stamp('tier:Bathroom', true, 15)],
        now: 99,
      );

      expect(result.tiers.keys, containsAll(['Kitchen', 'Bathroom']));
      expect(_only(result, 'a').isCompleted, isTrue);
      expect(result.remote.map((s) => s.id), [
        'a',
        'tier:Bathroom',
        'tier:Kitchen',
      ]);
    });

    test('merging the result again changes nothing', () {
      final first = mergeProgress(
        local: _catalog([_item('a')]),
        localTiers: {
          'Kitchen': tier('Kitchen', true, 0),
          'Food Storage': tier('Food Storage', true, 40),
        },
        remote: [
          _stamp('tier:Food Storage', false, 20),
          _stamp('tier:Bathroom', true, 50),
        ],
        now: 77,
      );
      final second = mergeProgress(
        local: first.challenges,
        localTiers: first.tiers,
        remote: first.remote,
        now: 1000,
      );

      expect(second.tiersChanged, isFalse);
      expect(second.remoteChanged, isFalse);
      expect(second.tiers, first.tiers);
    });

    test('nothing unlocked anywhere leaves everything empty', () {
      final result = mergeProgress(
        local: _catalog([_item('a')]),
        remote: const [],
        now: 77,
      );

      expect(result.tiers, isEmpty);
      expect(result.tiersChanged, isFalse);
    });
  });

  test(
    'ChecklistItem keeps updatedAt through JSON, and omits it when null',
    () {
      final item = _item('a', done: true, at: 123);

      expect(ChecklistItem.fromJson(item.toJson()).updatedAt, 123);
      expect(_item('b').toJson().containsKey('updatedAt'), isFalse);
    },
  );
}
