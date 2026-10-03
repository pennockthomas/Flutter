// The browser's storage backend (localStorage via SharedPreferences), plus
// the repository running on top of it: seeding, saving, and the import /
// backup / restore flow must behave exactly as they do with real files.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/challenge_repository.dart';
import 'package:flut/text_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PrefsTextStore', () {
    test('round-trips text and reports existence', () async {
      final store = PrefsTextStore();

      expect(await store.exists('a.json'), isFalse);
      expect(await store.read('a.json'), isNull);

      await store.write('a.json', '{"x": 1}');
      expect(await store.exists('a.json'), isTrue);
      expect(await store.read('a.json'), '{"x": 1}');

      await store.write('a.json', 'replaced');
      expect(await store.read('a.json'), 'replaced');

      await store.delete('a.json');
      expect(await store.exists('a.json'), isFalse);
    });

    test('keeps names separate and out of ordinary preference keys', () async {
      final store = PrefsTextStore();
      await store.write('a', '1');
      await store.write('b', '2');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'store.a', 'store.b'});
      expect(await store.read('a'), '1');
      expect(await store.read('b'), '2');
    });
  });

  group('ChallengeRepository on the browser store', () {
    late ChallengeRepository repository;

    setUp(() => repository = ChallengeRepository(store: PrefsTextStore()));

    test('seeds on first load and persists across repositories', () async {
      final first = await repository.loadChallenges();
      expect(first.containsKey('Kitchen'), isTrue);

      final kitchen = first['Kitchen']!;
      await repository.saveChallenges(
        {
          ...first,
          'Kitchen': kitchen.copyWith(
            checklist: [
              kitchen.checklist.first.copyWith(isCompleted: true),
              ...kitchen.checklist.skip(1),
            ],
          ),
        }.values,
      );

      // A page reload is a brand-new repository over the same storage.
      final reloaded = await ChallengeRepository(
        store: PrefsTextStore(),
      ).loadChallenges();
      expect(reloaded['Kitchen']!.checklist.first.isCompleted, isTrue);
    });

    test('export, import, backup and restore round-trip', () async {
      final seeded = await repository.loadChallenges();
      final exported = (await repository.exportJson())!;
      expect(repository.isValidImportJson(exported), isTrue);

      // Change the saved data, then import the earlier export over it.
      final withoutKitchen = Map.of(seeded)..remove('Kitchen');
      withoutKitchen['Start'] = seeded['Start']!.copyWith(
        unlocks: seeded['Start']!.unlocks
            .where((id) => id != 'Kitchen')
            .toList(),
      );
      await repository.saveChallenges(withoutKitchen.values);
      expect(await repository.hasImportBackup(), isFalse);

      expect(await repository.importFromJson(exported), isTrue);
      expect(await repository.hasImportBackup(), isTrue);
      expect(
        (await repository.loadChallenges()).containsKey('Kitchen'),
        isTrue,
      );

      // The backup holds what was there *before* the import.
      expect(await repository.restoreImportBackup(), isTrue);
      expect(
        (await repository.loadChallenges()).containsKey('Kitchen'),
        isFalse,
      );
    });

    test('exportJson is null before anything is saved', () async {
      expect(await repository.exportJson(), isNull);
    });

    test('there is no file path to hand out', () async {
      expect(repository.editableFilePath(), throwsUnsupportedError);
    });
  });
}
