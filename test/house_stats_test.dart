// The numbers behind the house stats: swaps per day, the running total for
// the graph, and the rankings.

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/house_models.dart';
import 'package:flut/house_stats.dart';

int _ms(int y, int m, int d, [int h = 12]) =>
    DateTime(y, m, d, h).millisecondsSinceEpoch;

Map<String, Challenge> _catalog(List<ChecklistItem> items) => {
  'Kitchen': Challenge(
    label: 'Kitchen',
    description: '',
    unlocks: const [],
    checklist: items,
  ),
};

ChecklistItem _item(String id, {bool done = true, int? at}) =>
    ChecklistItem(id: id, label: id, isCompleted: done, updatedAt: at);

HouseMember _member(
  String name, {
  int completed = 0,
  Map<String, int> days = const {},
}) => HouseMember(
  uid: name.toLowerCase(),
  name: name,
  completed: completed,
  total: 100,
  days: days,
);

void main() {
  group('dayKey', () {
    test('is the zero-padded local date', () {
      expect(dayKey(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('dailyCounts', () {
    final now = DateTime(2026, 10, 7, 20);

    test('counts the swaps that are done, on the day they were ticked', () {
      final days = dailyCounts(
        _catalog([
          _item('a', at: _ms(2026, 10, 5)),
          _item('b', at: _ms(2026, 10, 5, 23)),
          _item('c', at: _ms(2026, 10, 6)),
        ]),
        now: now,
      );

      expect(days, {'2026-10-05': 2, '2026-10-06': 1});
    });

    test('ignores swaps that are not done, or have no timestamp', () {
      final days = dailyCounts(
        _catalog([
          _item('undone', done: false, at: _ms(2026, 10, 5)),
          _item('legacy'),
          _item('zero', at: 0),
          _item('real', at: _ms(2026, 10, 5)),
        ]),
        now: now,
      );

      expect(days, {'2026-10-05': 1});
    });

    test('keeps only the last maxDays days', () {
      final days = dailyCounts(
        _catalog([
          _item('old', at: _ms(2024, 1, 1)),
          _item('recent', at: _ms(2026, 10, 1)),
        ]),
        now: now,
        maxDays: 400,
      );

      expect(days.keys, ['2026-10-01']);
    });

    test('counts across challenges', () {
      final days = dailyCounts({
        ..._catalog([_item('a', at: _ms(2026, 10, 5))]),
        'Bathroom': Challenge(
          label: 'Bathroom',
          description: '',
          unlocks: const [],
          checklist: [_item('b', at: _ms(2026, 10, 5))],
        ),
      }, now: now);

      expect(days, {'2026-10-05': 2});
    });
  });

  group('baselineOf', () {
    test('is what was done without a known day', () {
      final member = _member('Sam', completed: 10, days: {'2026-10-05': 3});

      expect(baselineOf(member), 7);
    });

    test('is never negative', () {
      final member = _member('Sam', completed: 2, days: {'2026-10-05': 5});

      expect(baselineOf(member), 0);
    });
  });

  group('cumulativeSeries', () {
    test('runs from the start level up, one point per day', () {
      final member = _member(
        'Sam',
        completed: 10,
        days: {'2026-10-02': 2, '2026-10-04': 3},
      );

      final series = cumulativeSeries(
        member,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 5),
      );

      expect(series.map((p) => p.total), [5, 7, 7, 10, 10]);
      expect(series.first.day, DateTime(2026, 10, 1));
      expect(series.length, 5);
    });

    test('starting later folds the earlier days into the first point', () {
      final member = _member(
        'Sam',
        completed: 10,
        days: {'2026-10-02': 2, '2026-10-04': 3},
      );

      final series = cumulativeSeries(
        member,
        from: DateTime(2026, 10, 3),
        to: DateTime(2026, 10, 5),
      );

      expect(series.map((p) => p.total), [7, 10, 10]);
    });

    test('someone with no history is a flat line at their total', () {
      final series = cumulativeSeries(
        _member('Lena', completed: 4),
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 3),
      );

      expect(series.map((p) => p.total), [4, 4, 4]);
    });

    test('crosses month ends', () {
      final series = cumulativeSeries(
        _member('Sam', completed: 1, days: {'2026-11-01': 1}),
        from: DateTime(2026, 10, 30),
        to: DateTime(2026, 11, 2),
      );

      expect(series.map((p) => dayKey(p.day)), [
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
        '2026-11-02',
      ]);
      expect(series.map((p) => p.total), [0, 0, 1, 1]);
    });
  });

  group('doneThisWeek', () {
    test('adds up today and the six days before', () {
      final member = _member(
        'Sam',
        days: {
          '2026-10-07': 2,
          '2026-10-01': 4,
          '2026-09-30': 9, // 7 days back: not counted
        },
      );

      expect(doneThisWeek(member, now: DateTime(2026, 10, 7)), 6);
    });
  });

  group('rankMembers', () {
    test('orders highest first and lets ties share a rank', () {
      final ranked = rankMembers([
        _member('Lena', completed: 5),
        _member('Sam', completed: 20),
        _member('Mila', completed: 20),
        _member('Ben', completed: 1),
      ], (m) => m.completed);

      expect(ranked.map((r) => r.member.name), ['Mila', 'Sam', 'Lena', 'Ben']);
      expect(ranked.map((r) => r.rank), [1, 1, 3, 4]);
    });

    test('an empty house has an empty ranking', () {
      expect(rankMembers([], (m) => m.completed), isEmpty);
    });
  });

  group('House and HouseMember', () {
    test('house names are tidied and limited', () {
      expect(House.cleanName('  Our   house '), 'Our house');
      expect(House.cleanName('   '), isNull);
      expect(House.cleanName('x' * (House.maxNameLength + 1)), isNull);
      expect(House.cleanName('x' * House.maxNameLength), isNotNull);
    });

    test('a member is read from stored data, skipping anything malformed', () {
      final member = HouseMember.fromData('u1', {
        'name': 'Sam',
        'completed': 12,
        'total': 118,
        'days': {
          '2026-10-05': 3,
          'not-a-date': 4,
          '2026-10-06': -2,
          '2026-10-07': 'many',
        },
      });

      expect(member.days, {'2026-10-05': 3});
      expect(member.progress, closeTo(12 / 118, 1e-9));
    });

    test('a house is read from stored data', () {
      final house = House.fromData('h1', {
        'name': 'Our house',
        'memberUids': ['a', 'b', 3],
        'createdBy': 'a',
      });

      expect(house.memberUids, ['a', 'b']);
      expect(house.hasMember('b'), isTrue);
      expect(house.isFull, isFalse);
    });

    test('an invite has an id made of the house and the person asked', () {
      const invite = HouseInvite(
        houseId: 'h1',
        houseName: 'Our house',
        from: 'a',
        fromName: 'Anna',
        to: 'b',
      );

      expect(invite.id, 'h1_b');
      expect(HouseInvite.fromData(invite.toData()).to, 'b');
    });
  });
}
