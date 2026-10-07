// End-to-end behaviour of per-account progress sync, against an in-memory
// stand-in for Firestore: what happens on sign-in, on local ticks, when
// another device changes something, when accounts switch, and on failures.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flut/challenge_model.dart';
import 'package:flut/challenge_store.dart';
import 'package:flut/progress_merge.dart';
import 'package:flut/progress_remote.dart';
import 'package:flut/progress_state_sync.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

class _FakeRemote implements ProgressRemote {
  final Map<String, List<ItemStamp>> docs = {};
  final Map<String, StreamController<List<ItemStamp>>> _streams = {};
  int writes = 0;
  int failNext = 0;

  StreamController<List<ItemStamp>> _stream(String uid) =>
      _streams.putIfAbsent(uid, StreamController.broadcast);

  /// Another device changing the cloud copy.
  void otherDeviceWrites(String uid, List<ItemStamp> state) {
    docs[uid] = state;
    _stream(uid).add(state);
  }

  @override
  Future<void> exchange(
    String uid,
    Future<MergeResult> Function(List<ItemStamp> remote) merge,
  ) async {
    if (failNext > 0) {
      failNext--;
      throw StateError('offline');
    }
    final result = await merge(docs[uid] ?? const []);
    if (result.remoteChanged) {
      docs[uid] = result.remote;
      writes++;
    }
  }

  @override
  Stream<List<ItemStamp>> watch(String uid) => _stream(uid).stream;
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

  late Directory tempDir;
  late _FakeRemote remote;
  late StreamController<String?> uids;
  late ProgressStateSync sync;
  final store = ChallengeStore.instance;

  ChecklistItem item(String id) => store.challenges.values
      .expand((c) => c.checklist)
      .firstWhere((i) => i.id == id);

  Future<void> tick(String id, bool done) async {
    final updated = {
      for (final entry in store.challenges.entries)
        entry.key: entry.value.copyWith(
          checklist: [
            for (final i in entry.value.checklist)
              i.id == id ? i.copyWith(isCompleted: done) : i,
          ],
        ),
    };
    await store.save(updated);
  }

  Future<void> signIn(String uid) async {
    final before = sync.completedSyncs;
    uids.add(uid);
    await _until(
      () => sync.completedSyncs > before,
      reason: 'sign-in sync to finish',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('progress_state_sync_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    await store.reload();
    remote = _FakeRemote();
    uids = StreamController<String?>();
    sync = ProgressStateSync(
      remote: remote,
      debounce: const Duration(milliseconds: 10),
      firstRetry: const Duration(milliseconds: 20),
      maxRetry: const Duration(milliseconds: 50),
    )..start(uids: uids.stream);
  });

  tearDown(() async {
    await sync.dispose();
    await uids.close();
    tempDir.deleteSync(recursive: true);
  });

  test('signing in uploads progress already made on this device', () async {
    await tick('kitchen.metal-knives', true);

    await signIn('anna');

    final doc = remote.docs['anna']!;
    expect(doc.map((s) => s.id), ['kitchen.metal-knives']);
    expect(doc.single.done, isTrue);
  });

  test(
    'signing in on a fresh device brings the account progress down',
    () async {
      remote.docs['anna'] = [_stamp('kitchen.metal-knives', true, 500)];

      uids.add('anna');
      await _until(
        () => item('kitchen.metal-knives').isCompleted,
        reason: 'cloud tick to reach the device',
      );

      expect(item('kitchen.metal-knives').updatedAt, 500);
    },
  );

  test('a tick made after signing in reaches the cloud', () async {
    await signIn('anna');

    await tick('kitchen.wooden-spoons', true);

    await _until(
      () =>
          remote.docs['anna']?.any((s) => s.id == 'kitchen.wooden-spoons') ??
          false,
      reason: 'tick to upload',
    );
    expect(remote.docs['anna']!.single.done, isTrue);
  });

  test('unticking reaches the cloud as an untick, not a deletion', () async {
    await signIn('anna');
    await tick('kitchen.wooden-spoons', true);
    await _until(() => remote.writes == 1, reason: 'tick upload');

    await tick('kitchen.wooden-spoons', false);

    await _until(() => remote.writes == 2, reason: 'untick upload');
    expect(remote.docs['anna']!.single.done, isFalse);
  });

  test(
    'a change from another device appears here without being re-uploaded',
    () async {
      await signIn('anna');
      final writesBefore = remote.writes;

      remote.otherDeviceWrites('anna', [
        _stamp(
          'kitchen.cast-iron-pan',
          true,
          DateTime.now().millisecondsSinceEpoch + 1000,
        ),
      ]);

      await _until(
        () => item('kitchen.cast-iron-pan').isCompleted,
        reason: 'other device change to arrive',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(remote.writes, writesBefore);
    },
  );

  test(
    'a different account starts from its own progress, not the last one',
    () async {
      await tick('kitchen.metal-knives', true);
      await signIn('anna');
      remote.docs['ben'] = [_stamp('kitchen.cast-iron-pan', true, 700)];

      uids.add('ben');
      await _until(
        () => item('kitchen.cast-iron-pan').isCompleted,
        reason: "ben's progress to arrive",
      );

      expect(item('kitchen.metal-knives').isCompleted, isFalse);
      expect(
        remote.docs['ben']!.map((s) => s.id),
        isNot(contains('kitchen.metal-knives')),
        reason: "anna's swaps must not leak into ben's account",
      );
      expect(remote.docs['anna']!.single.id, 'kitchen.metal-knives');
    },
  );

  test('signing out keeps the progress and stops syncing', () async {
    await signIn('anna');
    await tick('kitchen.metal-knives', true);
    await _until(() => remote.writes == 1, reason: 'upload');

    uids.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tick('kitchen.wooden-spoons', true);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(item('kitchen.metal-knives').isCompleted, isTrue);
    expect(item('kitchen.wooden-spoons').isCompleted, isTrue);
    expect(remote.writes, 1);
  });

  test('a failed sync is retried', () async {
    remote.failNext = 2;
    await tick('kitchen.metal-knives', true);

    uids.add('anna');

    await _until(
      () => remote.docs['anna']?.isNotEmpty ?? false,
      reason: 'retry to succeed',
    );
  });
}

ItemStamp _stamp(String id, bool done, int at) =>
    ItemStamp(id: id, done: done, at: at);
