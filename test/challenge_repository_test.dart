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

  test('reads the legacy bare-list save format for backwards compatibility',
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
  });
}
