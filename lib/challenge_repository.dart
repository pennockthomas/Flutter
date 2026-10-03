import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'challenge_model.dart';
import 'file_text_store.dart';
import 'text_store.dart';

class ChallengeRepository {
  /// [store] defaults to the right one for the platform (files on devices,
  /// browser storage on the web); tests pass their own.
  ChallengeRepository({TextStore? store})
    : _store = store ?? createDefaultTextStore();

  final TextStore _store;

  static const String seedAssetPath = 'assets/data/challenge.json';
  static const String editableFileName = 'challenge_editor.json';
  static const String importBackupFileName =
      'challenge_editor.pre_import_backup.json';

  Future<Map<String, Challenge>> loadChallenges() async {
    final seedChallenges = _withSeedItemIds(
      _decodeChallenges(await rootBundle.loadString(seedAssetPath)),
    );

    final savedText = await _store.read(editableFileName);
    if (savedText == null) {
      await _writeChallengeFile(
        seedChallenges.values,
        seedChallenges.keys.toSet(),
      );
      return seedChallenges;
    }

    final saved = _decodeChallengeFile(savedText);
    final mergedChallenges = _mergeSeedDefaults(
      seedChallenges: seedChallenges,
      editableChallenges: _assignItemIds(saved.challenges, seedChallenges),
      previouslySeenSeedIds: saved.seenSeedIds,
    );

    // Remember every seed id we've ever shown, so a challenge the user
    // deleted or renamed away from isn't re-added from the seed on a later
    // load just because its id is momentarily absent from the saved file.
    final updatedSeenSeedIds = {...saved.seenSeedIds, ...seedChallenges.keys};

    await _writeChallengeFile(mergedChallenges.values, updatedSeenSeedIds);
    return mergedChallenges;
  }

  Future<void> saveChallenges(Iterable<Challenge> challenges) async {
    final savedText = await _store.read(editableFileName);
    final seenSeedIds = savedText != null
        ? _decodeChallengeFile(savedText).seenSeedIds
        : <String>{};
    await _writeChallengeFile(challenges, seenSeedIds);
  }

  /// Replaces the saved challenge data with [jsonText] if (and only if) it
  /// parses as a valid save file (either the current or legacy format).
  /// Returns whether the import succeeded; on failure, existing data is
  /// left untouched.
  Future<bool> importFromJson(String jsonText) async {
    if (!isValidImportJson(jsonText)) return false;

    final currentText = await _store.read(editableFileName);
    if (currentText != null) {
      await _store.write(importBackupFileName, currentText);
    } else {
      await _store.delete(importBackupFileName);
    }
    await _store.write(editableFileName, jsonText);
    return true;
  }

  bool isValidImportJson(String jsonText) {
    try {
      final saved = _decodeChallengeFile(jsonText);
      _validateChallengeGraph(saved.challenges);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasImportBackup() => _store.exists(importBackupFileName);

  Future<bool> restoreImportBackup() async {
    final backupText = await _store.read(importBackupFileName);
    if (backupText == null) return false;

    try {
      _decodeChallengeFile(backupText);
    } catch (_) {
      return false;
    }

    await _store.write(editableFileName, backupText);
    return true;
  }

  Future<void> resetEditableChallenges() => _store.delete(editableFileName);

  /// The saved progress as JSON text, for exporting; null if nothing has
  /// been saved yet.
  Future<String?> exportJson() => _store.read(editableFileName);

  /// Path of the save file. Only exists when backed by real files, so this
  /// is for tests that need to plant or inspect the file directly.
  @visibleForTesting
  Future<String> editableFilePath() async {
    final store = _store;
    if (store is! FileTextStore) {
      throw UnsupportedError('This platform stores progress without a file.');
    }
    return store.pathFor(editableFileName);
  }

  Map<String, Challenge> _decodeChallenges(String jsonText) {
    final decodedData = jsonDecode(jsonText) as List<dynamic>;
    return _decodeChallengeList(decodedData);
  }

  _SavedChallengeFile _decodeChallengeFile(String jsonText) {
    final decoded = jsonDecode(jsonText);

    // Older saves were a bare list of challenges with no seen-ids tracking.
    if (decoded is List) {
      return _SavedChallengeFile(
        challenges: _decodeChallenges(jsonText),
        seenSeedIds: const {},
      );
    }

    final map = decoded as Map<String, dynamic>;
    final challengesJson = map['challenges'] as List<dynamic>;
    return _SavedChallengeFile(
      challenges: _decodeChallengeList(challengesJson),
      seenSeedIds: {
        for (final id in (map['seenSeedIds'] as List<dynamic>? ?? const []))
          id as String,
      },
    );
  }

  Map<String, Challenge> _decodeChallengeList(List<dynamic> items) {
    final challenges = <String, Challenge>{};
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final id = map['id'] as String;
      if (id.trim().isEmpty || challenges.containsKey(id)) {
        throw const FormatException(
          'Challenge IDs must be unique and non-empty.',
        );
      }
      challenges[id] = Challenge.fromJson(map);
    }
    return challenges;
  }

  /// Seed items that don't spell out an id get one derived from their
  /// challenge and label, so the same seed gives the same ids on every device.
  Map<String, Challenge> _withSeedItemIds(Map<String, Challenge> seed) {
    return {
      for (final entry in seed.entries)
        entry.key: entry.value.copyWith(
          checklist: [
            for (final item in entry.value.checklist)
              item.hasId
                  ? item
                  : item.copyWith(
                      id: ChecklistItem.derivedId(entry.key, item.label),
                    ),
          ],
        ),
    };
  }

  /// Migration for saves from before items had ids. An item with no id takes
  /// the id of the seed item with the same label in the same challenge, so
  /// the swaps people already have keep a shared identity; anything else (an
  /// item the user added or reworded) gets a fresh one. Ids already present
  /// are kept, except that a repeated id (a hand-edited or doubly imported
  /// file) is replaced so every id is unique across the whole catalog.
  Map<String, Challenge> _assignItemIds(
    Map<String, Challenge> challenges,
    Map<String, Challenge> seedChallenges,
  ) {
    final reserved = <String>{
      for (final challenge in challenges.values)
        for (final item in challenge.checklist)
          if (item.hasId) item.id,
    };
    final used = <String>{};

    String fresh() {
      var id = ChecklistItem.newId();
      while (reserved.contains(id) || used.contains(id)) {
        id = ChecklistItem.newId();
      }
      return id;
    }

    final result = <String, Challenge>{};
    for (final entry in challenges.entries) {
      final seedItems = seedChallenges[entry.key]?.checklist ?? const [];
      final items = <ChecklistItem>[];
      for (final item in entry.value.checklist) {
        String id;
        if (item.hasId) {
          id = used.contains(item.id) ? fresh() : item.id;
        } else {
          final match = seedItems
              .where(
                (seedItem) =>
                    seedItem.label == item.label &&
                    !reserved.contains(seedItem.id) &&
                    !used.contains(seedItem.id),
              )
              .firstOrNull;
          id = match?.id ?? fresh();
        }
        used.add(id);
        items.add(item.copyWith(id: id));
      }
      result[entry.key] = entry.value.copyWith(checklist: items);
    }
    return result;
  }

  void _validateChallengeGraph(Map<String, Challenge> challenges) {
    if (!challenges.containsKey('Start')) {
      throw const FormatException('A Start challenge is required.');
    }

    for (final challenge in challenges.values) {
      final uniqueUnlocks = <String>{};
      for (final unlockedId in challenge.unlocks) {
        if (!challenges.containsKey(unlockedId)) {
          throw FormatException(
            '${challenge.label} unlocks a missing challenge: $unlockedId',
          );
        }
        if (!uniqueUnlocks.add(unlockedId)) {
          throw FormatException(
            '${challenge.label} contains a duplicate unlock: $unlockedId',
          );
        }
      }
    }

    final visiting = <String>{};
    final visited = <String>{};

    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw const FormatException(
          'Challenge unlocks must not contain cycles.',
        );
      }
      for (final childId in challenges[id]!.unlocks) {
        visit(childId);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in challenges.keys) {
      visit(id);
    }
  }

  Map<String, Challenge> _mergeSeedDefaults({
    required Map<String, Challenge> seedChallenges,
    required Map<String, Challenge> editableChallenges,
    required Set<String> previouslySeenSeedIds,
  }) {
    final merged = Map<String, Challenge>.from(editableChallenges);

    for (final seedEntry in seedChallenges.entries) {
      final editableChallenge = merged[seedEntry.key];
      if (editableChallenge == null) {
        if (previouslySeenSeedIds.contains(seedEntry.key)) {
          // The user deleted or renamed this challenge away; respect that
          // instead of resurrecting it from the seed data.
          continue;
        }
        merged[seedEntry.key] = seedEntry.value;
        continue;
      }

      if (editableChallenge.checklist.isEmpty &&
          seedEntry.value.checklist.isNotEmpty) {
        merged[seedEntry.key] = editableChallenge.copyWith(
          checklist: seedEntry.value.checklist,
        );
      }
    }

    return merged;
  }

  Future<void> _writeChallengeFile(
    Iterable<Challenge> challenges,
    Set<String> seenSeedIds,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await _store.write(
      editableFileName,
      encoder.convert({
        'seenSeedIds': seenSeedIds.toList()..sort(),
        'challenges': challenges.map((c) => c.toJson()).toList(),
      }),
    );
  }
}

class _SavedChallengeFile {
  final Map<String, Challenge> challenges;
  final Set<String> seenSeedIds;

  const _SavedChallengeFile({
    required this.challenges,
    required this.seenSeedIds,
  });
}
