// How a new version of the built-in swap list (assets/data/challenge.json)
// reaches devices that already have a saved copy, and the clean export a
// developer uses to produce the next version.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/challenge_repository.dart';
import 'package:flut/text_store.dart';

class _MemoryStore implements TextStore {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String name) async => files[name];

  @override
  Future<void> write(String name, String text) async => files[name] = text;

  @override
  Future<bool> exists(String name) async => files.containsKey(name);

  @override
  Future<void> delete(String name) async => files.remove(name);
}

String _seed(int version, List<Map<String, Object?>> challenges) =>
    jsonEncode({'version': version, 'challenges': challenges});

Map<String, Object?> _challenge(
  String id, {
  List<String> unlocks = const [],
  List<(String, String)> items = const [],
  String description = '',
}) => {
  'id': id,
  'description': description,
  'unlocks': unlocks,
  'checklist': [
    for (final (itemId, label) in items) {'id': itemId, 'label': label},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStore store;
  late String seedText;
  late ChallengeRepository repository;

  setUp(() {
    store = _MemoryStore();
    seedText = _seed(1, [
      _challenge('Start', unlocks: ['Kitchen']),
      _challenge(
        'Kitchen',
        items: [('k.knives', 'Metal knives'), ('k.spoons', 'Wooden spoons')],
      ),
    ]);
    repository = ChallengeRepository(
      store: store,
      loadSeed: () async => seedText,
    );
  });

  Future<Map<String, Challenge>> tickKnives() async {
    final challenges = await repository.loadChallenges();
    final kitchen = challenges['Kitchen']!;
    await repository.saveChallenges(
      {
        ...challenges,
        'Kitchen': kitchen.copyWith(
          checklist: [
            kitchen.checklist.first.copyWith(isCompleted: true, updatedAt: 500),
            ...kitchen.checklist.skip(1),
          ],
        ),
      }.values,
    );
    return repository.loadChallenges();
  }

  List<String> labels(Map<String, Challenge> c, String id) =>
      c[id]!.checklist.map((i) => i.label).toList();

  test('a newer list adds swaps to a challenge that already existed', () async {
    await tickKnives();
    seedText = _seed(2, [
      _challenge('Start', unlocks: ['Kitchen']),
      _challenge(
        'Kitchen',
        items: [
          ('k.knives', 'Metal knives'),
          ('k.spoons', 'Wooden spoons'),
          ('k.pan', 'Cast iron pan'),
        ],
      ),
    ]);

    final updated = await repository.loadChallenges();

    expect(labels(updated, 'Kitchen'), [
      'Metal knives',
      'Wooden spoons',
      'Cast iron pan',
    ]);
  });

  test('ticks are kept, matched by swap id', () async {
    await tickKnives();
    seedText = _seed(2, [
      _challenge('Start', unlocks: ['Kitchen']),
      _challenge('Kitchen', items: [('k.knives', 'Steel knives')]),
    ]);

    final updated = await repository.loadChallenges();

    final knives = updated['Kitchen']!.checklist.single;
    expect(knives.label, 'Steel knives', reason: 'the rename is taken');
    expect(knives.isCompleted, isTrue, reason: 'the tick is kept');
    expect(knives.updatedAt, 500);
  });

  test('a swap that moves to another challenge keeps its tick', () async {
    await tickKnives();
    seedText = _seed(2, [
      _challenge('Start', unlocks: ['Kitchen', 'Tools']),
      _challenge('Kitchen', items: [('k.spoons', 'Wooden spoons')]),
      _challenge('Tools', items: [('k.knives', 'Metal knives')]),
    ]);

    final updated = await repository.loadChallenges();

    expect(updated['Tools']!.checklist.single.isCompleted, isTrue);
  });

  test('removed swaps and challenges disappear, new ones appear', () async {
    await tickKnives();
    seedText = _seed(2, [
      _challenge('Start', unlocks: ['Bathroom']),
      _challenge('Bathroom', items: [('b.brush', 'Bamboo toothbrush')]),
    ]);

    final updated = await repository.loadChallenges();

    expect(updated.keys, ['Start', 'Bathroom']);
    expect(labels(updated, 'Bathroom'), ['Bamboo toothbrush']);
  });

  test('device-only edits are replaced by the new list', () async {
    final challenges = await repository.loadChallenges();
    final kitchen = challenges['Kitchen']!;
    await repository.saveChallenges(
      {
        ...challenges,
        'Kitchen': kitchen.copyWith(
          checklist: [...kitchen.checklist, ChecklistItem.create('My gadget')],
        ),
      }.values,
    );
    seedText = _seed(2, [
      _challenge('Start', unlocks: ['Kitchen']),
      _challenge('Kitchen', items: [('k.knives', 'Metal knives')]),
    ]);

    final updated = await repository.loadChallenges();

    expect(labels(updated, 'Kitchen'), ['Metal knives']);
  });

  test('the same version leaves device edits alone', () async {
    final challenges = await repository.loadChallenges();
    final kitchen = challenges['Kitchen']!;
    await repository.saveChallenges(
      {
        ...challenges,
        'Kitchen': kitchen.copyWith(
          checklist: [...kitchen.checklist, ChecklistItem.create('My gadget')],
        ),
      }.values,
    );

    final reloaded = await repository.loadChallenges();

    expect(labels(reloaded, 'Kitchen'), [
      'Metal knives',
      'Wooden spoons',
      'My gadget',
    ]);
  });

  test(
    'a save from before versions existed keeps its edits the first time',
    () async {
      store.files['challenge_editor.json'] = jsonEncode({
        'seenSeedIds': ['Start', 'Kitchen'],
        'challenges': [
          _challenge('Start', unlocks: ['Kitchen']),
          _challenge('Kitchen', items: [('k.knives', 'My own wording')]),
        ],
      });

      final loaded = await repository.loadChallenges();

      expect(labels(loaded, 'Kitchen'), ['My own wording']);
      expect(
        (jsonDecode(store.files['challenge_editor.json']!)
            as Map)['seedVersion'],
        1,
      );
    },
  );

  test('a device on a newer list than the app is not downgraded', () async {
    await tickKnives();
    final text = jsonDecode(store.files['challenge_editor.json']!) as Map;
    text['seedVersion'] = 5;
    store.files['challenge_editor.json'] = jsonEncode(text);
    seedText = _seed(2, [_challenge('Start')]);

    final loaded = await repository.loadChallenges();

    expect(loaded.keys, contains('Kitchen'));
  });

  group('backup before an update', () {
    Future<void> addGadget() async {
      final challenges = await repository.loadChallenges();
      final kitchen = challenges['Kitchen']!;
      await repository.saveChallenges(
        {
          ...challenges,
          'Kitchen': kitchen.copyWith(
            checklist: [
              ...kitchen.checklist,
              ChecklistItem.create('My gadget'),
            ],
          ),
        }.values,
      );
    }

    void shipVersion2() {
      seedText = _seed(2, [
        _challenge('Start', unlocks: ['Kitchen']),
        _challenge('Kitchen', items: [('k.knives', 'Metal knives')]),
      ]);
    }

    test('no backup is made when nothing was replaced', () async {
      await addGadget();

      await repository.loadChallenges();

      expect(await repository.hasUpdateBackup(), isFalse);
    });

    test('an update keeps a copy of the list it replaced', () async {
      await addGadget();
      shipVersion2();

      await repository.loadChallenges();

      expect(await repository.hasUpdateBackup(), isTrue);
    });

    test('restoring brings the edits back and keeps newer ticks', () async {
      await addGadget();
      shipVersion2();
      final updated = await repository.loadChallenges();
      final knives = updated['Kitchen']!.checklist.single;
      await repository.saveChallenges(
        {
          ...updated,
          'Kitchen': updated['Kitchen']!.copyWith(
            checklist: [knives.copyWith(isCompleted: true, updatedAt: 900)],
          ),
        }.values,
      );

      expect(await repository.restoreUpdateBackup(), isTrue);
      final restored = await repository.loadChallenges();

      expect(labels(restored, 'Kitchen'), [
        'Metal knives',
        'Wooden spoons',
        'My gadget',
      ]);
      expect(restored['Kitchen']!.checklist.first.isCompleted, isTrue);
      expect(restored['Kitchen']!.checklist.first.updatedAt, 900);
    });

    test('a restored list is not replaced again on the next launch', () async {
      await addGadget();
      shipVersion2();
      await repository.loadChallenges();
      await repository.restoreUpdateBackup();

      final again = await repository.loadChallenges();

      expect(labels(again, 'Kitchen'), contains('My gadget'));
    });

    test('a later update does not overwrite the earlier backup', () async {
      await addGadget();
      shipVersion2();
      await repository.loadChallenges();
      seedText = _seed(3, [
        _challenge('Start', unlocks: ['Kitchen']),
        _challenge('Kitchen', items: [('k.knives', 'Metal knives')]),
      ]);
      await repository.loadChallenges();

      expect(await repository.restoreUpdateBackup(), isTrue);
      final restored = await repository.loadChallenges();

      // The latest copy (before version 3) is the clean version 2 list.
      expect(labels(restored, 'Kitchen'), ['Metal knives']);
      expect(
        store.files.containsKey(ChallengeRepository.updateBackupFileName(2)),
        isTrue,
        reason: 'the copy that holds the gadget is still there',
      );
      expect(
        store.files[ChallengeRepository.updateBackupFileName(2)],
        contains('My gadget'),
      );
    });

    test('restoring with no copy reports that it did nothing', () async {
      await repository.loadChallenges();

      expect(await repository.restoreUpdateBackup(), isFalse);
    });
  });

  group('exportSwapList', () {
    test('has the built-in format and none of the progress', () async {
      await tickKnives();

      final exported = jsonDecode((await repository.exportSwapList())!) as Map;

      expect(exported['version'], 1);
      final kitchen = (exported['challenges'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == 'Kitchen');
      expect(kitchen['checklist'], [
        {'id': 'k.knives', 'label': 'Metal knives'},
        {'id': 'k.spoons', 'label': 'Wooden spoons'},
      ]);
      expect(jsonEncode(exported), isNot(contains('completed')));
      expect(jsonEncode(exported), isNot(contains('updatedAt')));
    });

    test('can be used as the next list, and keeps the ids', () async {
      final challenges = await repository.loadChallenges();
      final kitchen = challenges['Kitchen']!;
      await repository.saveChallenges(
        {
          ...challenges,
          'Kitchen': kitchen.copyWith(
            checklist: [
              ...kitchen.checklist,
              ChecklistItem.create('My gadget'),
            ],
          ),
        }.values,
      );
      final exported = jsonDecode((await repository.exportSwapList())!) as Map;
      final addedId =
          ((exported['challenges'] as List)
                          .cast<Map<String, dynamic>>()
                          .firstWhere((c) => c['id'] == 'Kitchen')['checklist']
                      as List)
                  .cast<Map<String, dynamic>>()
                  .last['id']
              as String;

      exported['version'] = 2;
      seedText = jsonEncode(exported);
      final updated = await repository.loadChallenges();

      expect(labels(updated, 'Kitchen'), contains('My gadget'));
      expect(updated['Kitchen']!.checklist.last.id, addedId);
    });

    test('is null before anything has been saved', () async {
      expect(await repository.exportSwapList(), isNull);
    });
  });

  test(
    'the bundled list loads, has a version, and its ids are unique',
    () async {
      final real = ChallengeRepository(store: _MemoryStore());
      final challenges = await real.loadChallenges();
      final ids = [
        for (final c in challenges.values) ...c.checklist.map((i) => i.id),
      ];

      expect(ids, isNotEmpty);
      expect(ids.toSet().length, ids.length);
    },
  );
}
