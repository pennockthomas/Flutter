// Covers the pure summary logic behind both the Profile page's "Progress By
// Area" card and the progress copy uploaded to Firestore (Phase 3b).

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/progress_summary.dart';

Challenge _challenge(
  String label, {
  List<String> unlocks = const [],
  List<bool> items = const [],
}) {
  return Challenge(
    label: label,
    description: '',
    unlocks: unlocks,
    checklist: [
      for (var i = 0; i < items.length; i++)
        ChecklistItem(label: '$label $i', isCompleted: items[i]),
    ],
  );
}

Map<String, Challenge> _tree(List<Challenge> challenges) => {
  for (final challenge in challenges) challenge.label: challenge,
};

void main() {
  test('areas count every challenge beneath them, in Start order', () {
    final challenges = _tree([
      _challenge('Start', unlocks: ['Kitchen', 'Bathroom']),
      _challenge('Kitchen', unlocks: ['Food Storage'], items: [true, false]),
      _challenge('Food Storage', items: [true, true, false]),
      _challenge('Bathroom', items: [false]),
    ]);

    final areas = progressByArea(challenges);

    expect(areas.map((a) => a.label), ['Kitchen', 'Bathroom']);
    expect(areas[0].completed, 3);
    expect(areas[0].total, 5);
    expect(areas[1].completed, 0);
    expect(areas[1].total, 1);
  });

  test('areas with no checklist items are skipped', () {
    final challenges = _tree([
      _challenge('Start', unlocks: ['Kitchen', 'Empty']),
      _challenge('Kitchen', items: [true]),
      _challenge('Empty'),
    ]);

    expect(progressByArea(challenges).map((a) => a.label), ['Kitchen']);
  });

  test('a cycle in the unlock tree does not loop or double count', () {
    final challenges = _tree([
      _challenge('Start', unlocks: ['A']),
      _challenge('A', unlocks: ['B'], items: [true]),
      _challenge('B', unlocks: ['A'], items: [false]),
    ]);

    final areas = progressByArea(challenges);

    expect(areas.single.completed, 1);
    expect(areas.single.total, 2);
  });

  test('no Start challenge means no areas', () {
    expect(progressByArea(_tree([_challenge('Kitchen', items: [true])])), []);
  });

  test('summary has totals and areas but no item names', () {
    final challenges = _tree([
      _challenge('Start', unlocks: ['Kitchen']),
      _challenge('Kitchen', items: [true, false, true]),
    ]);

    final summary = buildProgressSummary(challenges);

    expect(summary['completed'], 2);
    expect(summary['total'], 3);
    expect(summary['areas'], [
      {'label': 'Kitchen', 'completed': 2, 'total': 3},
    ]);
    expect(summary.toString(), isNot(contains('Kitchen 0')));
  });
}
