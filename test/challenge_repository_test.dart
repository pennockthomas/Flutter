// Exercises ChallengeRepository directly against a temp directory, so the
// deletion/rename persistence behavior can be verified in under a second
// instead of rebuilding the app and poking the simulator.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/challenge_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChallengeRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('challenge_repository_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    repository = ChallengeRepository();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('loadChallenges seeds from the bundled asset on first run', () async {
    final challenges = await repository.loadChallenges();

    expect(challenges, isNotEmpty);
    expect(challenges.containsKey('Start'), isTrue);
    expect(challenges.containsKey('Kitchen'), isTrue);
  });

  test('saved checklist completion survives a reload', () async {
    final challenges = await repository.loadChallenges();
    final kitchen = challenges['Kitchen']!;
    final updatedChecklist = [
      kitchen.checklist.first.copyWith(isCompleted: true),
      ...kitchen.checklist.skip(1),
    ];
    final updated = {
      ...challenges,
      'Kitchen': kitchen.copyWith(checklist: updatedChecklist),
    };

    await repository.saveChallenges(updated.values);
    final reloaded = await repository.loadChallenges();

    expect(reloaded['Kitchen']!.checklist.first.isCompleted, isTrue);
  });

  test('deleting a seed challenge does not resurrect it on reload', () async {
    final challenges = await repository.loadChallenges();
    final withoutKitchen = Map.of(challenges)..remove('Kitchen');

    await repository.saveChallenges(withoutKitchen.values);
    final reloaded = await repository.loadChallenges();

    expect(reloaded.containsKey('Kitchen'), isFalse);
  });

  test('renaming a seed challenge does not bring back the old id', () async {
    final challenges = await repository.loadChallenges();
    final kitchen = challenges['Kitchen']!;
    final renamed = Map.of(challenges)
      ..remove('Kitchen')
      ..['Kitchen Renamed'] = kitchen.copyWith(label: 'Kitchen Renamed');

    await repository.saveChallenges(renamed.values);
    final reloaded = await repository.loadChallenges();

    expect(reloaded.containsKey('Kitchen'), isFalse);
    expect(reloaded.containsKey('Kitchen Renamed'), isTrue);
  });

  test(
    'reads the legacy bare-list save format for backwards compatibility',
    () async {
      // Older saves were a plain JSON list with no seenSeedIds tracking.
      final seedChallenges = await repository.loadChallenges();
      final filePath = await repository.editableFilePath();
      final legacyJson = jsonEncode(
        seedChallenges.values.map((Challenge c) => c.toJson()).toList(),
      );
      File(filePath).writeAsStringSync(legacyJson);

      final reloaded = await repository.loadChallenges();

      expect(reloaded.containsKey('Start'), isTrue);
      expect(reloaded.containsKey('Kitchen'), isTrue);
    },
  );

  group('importFromJson', () {
    test('replaces saved data with valid exported JSON', () async {
      final challenges = await repository.loadChallenges();
      final withoutKitchen = Map.of(challenges)
        ..remove('Kitchen')
        ..['Start'] = challenges['Start']!.copyWith(
          unlocks: challenges['Start']!.unlocks
              .where((id) => id != 'Kitchen')
              .toList(),
        );
      await repository.saveChallenges(withoutKitchen.values);
      final exportedJson = File(
        await repository.editableFilePath(),
      ).readAsStringSync();

      // A second, independent repository (e.g. after reinstalling the app)
      // imports what the first one exported.
      final freshTempDir = Directory.systemTemp.createTempSync(
        'challenge_import_test',
      );
      addTearDown(() => freshTempDir.deleteSync(recursive: true));
      PathProviderPlatform.instance = _FakePathProviderPlatform(
        freshTempDir.path,
      );
      final freshRepository = ChallengeRepository();

      final succeeded = await freshRepository.importFromJson(exportedJson);
      final imported = await freshRepository.loadChallenges();

      expect(succeeded, isTrue);
      expect(imported.containsKey('Kitchen'), isFalse);
    });

    test('keeps and restores the save that existed before import', () async {
      final original = await repository.loadChallenges();
      final originalKitchen = original['Kitchen']!;
      await repository.saveChallenges(
        {
          ...original,
          'Kitchen': originalKitchen.copyWith(
            checklist: [
              originalKitchen.checklist.first.copyWith(isCompleted: true),
              ...originalKitchen.checklist.skip(1),
            ],
          ),
        }.values,
      );

      final imported = Map.of(original)
        ..remove('Kitchen')
        ..['Start'] = original['Start']!.copyWith(
          unlocks: original['Start']!.unlocks
              .where((id) => id != 'Kitchen')
              .toList(),
        );
      final importedJson = jsonEncode({
        'seenSeedIds': original.keys.toList(),
        'challenges': imported.values
            .map((challenge) => challenge.toJson())
            .toList(),
      });

      expect(await repository.importFromJson(importedJson), isTrue);
      expect(await repository.hasImportBackup(), isTrue);
      expect(
        (await repository.loadChallenges()).containsKey('Kitchen'),
        isFalse,
      );

      expect(await repository.restoreImportBackup(), isTrue);
      final restored = await repository.loadChallenges();
      expect(restored['Kitchen']!.checklist.first.isCompleted, isTrue);
    });

    test('reports no restorable backup before an import', () async {
      expect(await repository.hasImportBackup(), isFalse);
      expect(await repository.restoreImportBackup(), isFalse);
    });

    test('accepts the legacy bare-list format', () async {
      final seedChallenges = await repository.loadChallenges();
      final legacyJson = jsonEncode(
        seedChallenges.values.map((Challenge c) => c.toJson()).toList(),
      );

      final succeeded = await repository.importFromJson(legacyJson);

      expect(succeeded, isTrue);
    });

    test('rejects malformed JSON without touching existing data', () async {
      final challenges = await repository.loadChallenges();

      final succeeded = await repository.importFromJson('{ not valid json');

      expect(succeeded, isFalse);
      final stillThere = await repository.loadChallenges();
      expect(stillThere.keys.toSet(), challenges.keys.toSet());
    });

    test('rejects well-formed JSON that is not a save file', () async {
      final succeeded = await repository.importFromJson('{"hello": "world"}');
      expect(succeeded, isFalse);
    });

    test('rejects duplicate challenge IDs', () async {
      final duplicateIds = jsonEncode([
        {
          'id': 'Start',
          'description': '',
          'unlocks': <String>[],
          'checklist': <dynamic>[],
        },
        {
          'id': 'Start',
          'description': 'Duplicate',
          'unlocks': <String>[],
          'checklist': <dynamic>[],
        },
      ]);

      expect(await repository.importFromJson(duplicateIds), isFalse);
    });

    test('rejects unlocks that reference a missing challenge', () async {
      final missingChild = jsonEncode([
        {
          'id': 'Start',
          'description': '',
          'unlocks': ['Missing'],
          'checklist': <dynamic>[],
        },
      ]);

      expect(await repository.importFromJson(missingChild), isFalse);
    });

    test('rejects cycles in the challenge tree', () async {
      final cycle = jsonEncode([
        {
          'id': 'Start',
          'description': '',
          'unlocks': ['Kitchen'],
          'checklist': <dynamic>[],
        },
        {
          'id': 'Kitchen',
          'description': '',
          'unlocks': ['Start'],
          'checklist': <dynamic>[],
        },
      ]);

      expect(await repository.importFromJson(cycle), isFalse);
    });
  });
}
