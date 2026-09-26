// Exercises the shared ChallengeStore: that ensureLoaded() caches instead of
// re-reading disk every time, that reload() forces a fresh read, and that
// save() persists and notifies listeners the way every screen relies on.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/challenge_repository.dart';
import 'package:flut/challenge_store.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('challenge_store_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    // ChallengeStore is a singleton that outlives individual tests, so force
    // it to drop any cached state and re-read from this test's fresh
    // temp directory before each test.
    await ChallengeStore.instance.reload();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ensureLoaded caches after the first call; reload forces a refresh',
      () async {
    final first = await ChallengeStore.instance.ensureLoaded();
    expect(first.containsKey('Kitchen'), isTrue);

    // Mutate the file on disk directly, bypassing the store.
    final withoutKitchen = Map.of(first)..remove('Kitchen');
    await ChallengeRepository().saveChallenges(withoutKitchen.values);

    final cached = await ChallengeStore.instance.ensureLoaded();
    expect(
      cached.containsKey('Kitchen'),
      isTrue,
      reason: 'ensureLoaded should return the cached value, not re-read disk',
    );

    final refreshed = await ChallengeStore.instance.reload();
    expect(refreshed.containsKey('Kitchen'), isFalse);
  });

  test('save updates the in-memory value, persists it, and notifies listeners',
      () async {
    await ChallengeStore.instance.ensureLoaded();

    Map<String, Challenge>? notifiedChallenges;
    void listener() => notifiedChallenges = ChallengeStore.instance.challenges;
    ChallengeStore.instance.addListener(listener);
    addTearDown(() => ChallengeStore.instance.removeListener(listener));

    final current = ChallengeStore.instance.challenges;
    final kitchen = current['Kitchen']!;
    final updated = {
      ...current,
      'Kitchen': kitchen.copyWith(
        checklist: [
          kitchen.checklist.first.copyWith(isCompleted: true),
          ...kitchen.checklist.skip(1),
        ],
      ),
    };

    await ChallengeStore.instance.save(updated);

    expect(notifiedChallenges, isNotNull);
    expect(notifiedChallenges!['Kitchen']!.checklist.first.isCompleted, isTrue);

    // Persisted to disk too, visible to a completely separate repository.
    final persisted = await ChallengeRepository().loadChallenges();
    expect(persisted['Kitchen']!.checklist.first.isCompleted, isTrue);
  });
}
