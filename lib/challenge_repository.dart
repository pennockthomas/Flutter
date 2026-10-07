import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge_model.dart';
import 'file_text_store.dart';
import 'progress_merge.dart';
import 'text_store.dart';

class ChallengeRepository {
  /// [store] defaults to the right one for the platform (files on devices,
  /// browser storage on the web); tests pass their own.
  ChallengeRepository({TextStore? store, Future<String> Function()? loadSeed})
    : _store = store ?? createDefaultTextStore(),
      _loadSeedText = loadSeed ?? (() => rootBundle.loadString(seedAssetPath));

  final TextStore _store;
  final Future<String> Function() _loadSeedText;

  static const String seedAssetPath = 'assets/data/challenge.json';
  static const String editableFileName = 'challenge_editor.json';
  static const String tiersFileName = 'tier_unlocks.json';

  /// Where unlocked tiers used to be kept (a plain list of labels).
  static const String legacyUnlockedNodesKey = 'unlocked_nodes';

  /// A copy of the saved list, kept when a newer built-in list replaces it
  /// (one file per list version, so a later update can't overwrite the copy
  /// that holds edits made earlier).
  static String updateBackupFileName(int version) =>
      'challenge_editor.pre_update_v$version.json';
  static const String importBackupFileName =
      'challenge_editor.pre_import_backup.json';

  /// The swap list that ships with the app, with no progress: the structure
  /// of a house's shared tree, so every member sees the same swaps.
  Future<Map<String, Challenge>> loadBundledCatalog() async =>
      _withSeedItemIds(_decodeSeed(await _loadSeedText()).challenges);

  Future<Map<String, Challenge>> loadChallenges() async {
    final seed = _decodeSeed(await _loadSeedText());
    final seedChallenges = _withSeedItemIds(seed.challenges);

    final savedText = await _store.read(editableFileName);
    if (savedText == null) {
      await _writeChallengeFile(
        seedChallenges.values,
        seedChallenges.keys.toSet(),
        seed.version,
      );
      return seedChallenges;
    }

    final saved = _decodeChallengeFile(savedText);
    final savedChallenges = _assignItemIds(saved.challenges, seedChallenges);

    // A save from before the list had a version is taken to be on the
    // current one, so the first launch after this change doesn't throw away
    // edits made on the device.
    final savedVersion = saved.seedVersion ?? seed.version;

    // Remember every seed id we've ever shown, so a challenge the user
    // deleted or renamed away from isn't re-added from the seed on a later
    // load just because its id is momentarily absent from the saved file.
    final updatedSeenSeedIds = {...saved.seenSeedIds, ...seedChallenges.keys};

    if (seed.version > savedVersion) {
      // A newer built-in list shipped with this app: take its structure
      // (new, renamed, removed and reordered swaps), keeping what the user
      // has ticked. The list as it was is kept, in case it held edits that
      // were never exported.
      await _store.write(updateBackupFileName(seed.version), savedText);
      final updated = _applySeedUpdate(seedChallenges, savedChallenges);
      await _writeChallengeFile(
        updated.values,
        updatedSeenSeedIds,
        seed.version,
      );
      return updated;
    }

    final mergedChallenges = _mergeSeedDefaults(
      seedChallenges: seedChallenges,
      editableChallenges: savedChallenges,
      previouslySeenSeedIds: saved.seenSeedIds,
    );
    await _writeChallengeFile(
      mergedChallenges.values,
      updatedSeenSeedIds,
      savedVersion,
    );
    return mergedChallenges;
  }

  /// The built-in list's structure, with the progress from [saved] carried
  /// over by swap id (so a swap that was renamed or moved keeps its tick).
  /// Challenges and swaps that aren't in [seed] are dropped, including ones
  /// added on this device with the Playground that were never exported.
  Map<String, Challenge> _applySeedUpdate(
    Map<String, Challenge> seed,
    Map<String, Challenge> saved,
  ) {
    final progress = <String, ChecklistItem>{
      for (final challenge in saved.values)
        for (final item in challenge.checklist) item.id: item,
    };
    return {
      for (final entry in seed.entries)
        entry.key: entry.value.copyWith(
          checklist: [
            for (final item in entry.value.checklist)
              switch (progress[item.id]) {
                final known? => item.copyWith(
                  isCompleted: known.isCompleted,
                  updatedAt: known.updatedAt,
                ),
                null => item,
              },
          ],
        ),
    };
  }

  /// The highest list version that has a pre-update copy on this device, or
  /// null if none. Looks no further than the list version the save is on.
  Future<int?> _latestUpdateBackupVersion() async {
    final savedText = await _store.read(editableFileName);
    final seed = _decodeSeed(await _loadSeedText());
    final upper = savedText == null
        ? seed.version
        : (_decodeChallengeFile(savedText).seedVersion ?? seed.version);
    for (var version = upper; version >= 2; version--) {
      if (await _store.exists(updateBackupFileName(version))) return version;
    }
    return null;
  }

  Future<bool> hasUpdateBackup() async =>
      await _latestUpdateBackupVersion() != null;

  /// Puts back the swap list as it was before the latest list update (see
  /// [updateBackupFileName]), keeping the ticks made since, and pins it to
  /// the current list version so the next launch doesn't replace it again.
  /// Returns false if there's no usable copy.
  Future<bool> restoreUpdateBackup() async {
    final version = await _latestUpdateBackupVersion();
    final savedText = await _store.read(editableFileName);
    if (version == null || savedText == null) return false;
    final backupText = await _store.read(updateBackupFileName(version));
    if (backupText == null) return false;

    try {
      final backup = _decodeChallengeFile(backupText);
      final current = _decodeChallengeFile(savedText);
      final seed = _withSeedItemIds(
        _decodeSeed(await _loadSeedText()).challenges,
      );
      final structure = _assignItemIds(backup.challenges, seed);
      final restored = _applySeedUpdate(structure, current.challenges);
      await _writeChallengeFile(restored.values, {
        ...current.seenSeedIds,
        ...backup.seenSeedIds,
      }, current.seedVersion);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The swap list as a developer would put it in
  /// `assets/data/challenge.json`: challenges, descriptions, unlocks and
  /// swaps with their ids, and none of the user's progress. Null if nothing
  /// has been saved yet. `version` is the list version this device is on;
  /// the next release should use one higher.
  Future<String?> exportSwapList() async {
    final savedText = await _store.read(editableFileName);
    if (savedText == null) return null;
    final saved = _decodeChallengeFile(savedText);
    final seed = _decodeSeed(await _loadSeedText());
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'version': saved.seedVersion ?? seed.version,
      'challenges': [
        for (final challenge in saved.challenges.values)
          {
            'id': challenge.label,
            'description': challenge.description,
            'unlocks': challenge.unlocks,
            'checklist': [
              for (final item in challenge.checklist)
                {'id': item.id, 'label': item.label},
            ],
          },
      ],
    });
  }

  /// The unlocked-tier state, keyed by label ([ItemStamp.done] = unlocked).
  /// Saves from before tiers had timestamps kept a bare list of labels in
  /// SharedPreferences; those are carried over (unstamped, so they're stamped
  /// the first time they're merged) and the old key is removed.
  Future<Map<String, ItemStamp>> loadTiers() async {
    final text = await _store.read(tiersFileName);
    if (text != null) {
      try {
        final decoded = jsonDecode(text) as Map<String, dynamic>;
        return {
          for (final entry in (decoded['tiers'] as List<dynamic>? ?? const []))
            (entry as Map<String, dynamic>)['id'] as String: ItemStamp(
              id: entry['id'] as String,
              done: entry['done'] as bool,
              at: (entry['at'] as num).toInt(),
            ),
        };
      } catch (e) {
        debugPrint('Unreadable tier file, starting without tiers: $e');
        return {};
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(legacyUnlockedNodesKey) ?? const [];
      final tiers = {
        for (final label in legacy)
          label: ItemStamp(id: label, done: true, at: 0),
      };
      if (legacy.isNotEmpty) {
        await saveTiers(tiers);
        await prefs.remove(legacyUnlockedNodesKey);
      }
      return tiers;
    } catch (e) {
      // No preferences to migrate from; start with nothing unlocked.
      debugPrint('Could not read the old tier list: $e');
      return {};
    }
  }

  Future<void> saveTiers(Map<String, ItemStamp> tiers) async {
    const encoder = JsonEncoder.withIndent('  ');
    final list = tiers.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    await _store.write(
      tiersFileName,
      encoder.convert({
        'tiers': [for (final tier in list) tier.toJson()],
      }),
    );
  }

  Future<void> saveChallenges(Iterable<Challenge> challenges) async {
    final savedText = await _store.read(editableFileName);
    final saved = savedText != null ? _decodeChallengeFile(savedText) : null;
    await _writeChallengeFile(
      challenges,
      saved?.seenSeedIds ?? <String>{},
      saved?.seedVersion,
    );
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

  /// The built-in list: `{"version": N, "challenges": [...]}`. A bare list
  /// (the format before versions) counts as version 1.
  _Seed _decodeSeed(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is List) {
      return _Seed(1, _decodeChallengeList(decoded));
    }
    final map = decoded as Map<String, dynamic>;
    return _Seed(
      (map['version'] as num?)?.toInt() ?? 1,
      _decodeChallengeList(map['challenges'] as List<dynamic>),
    );
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
      seedVersion: (map['seedVersion'] as num?)?.toInt(),
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
    int? seedVersion,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await _store.write(
      editableFileName,
      encoder.convert({
        'seedVersion': ?seedVersion,
        'seenSeedIds': seenSeedIds.toList()..sort(),
        'challenges': challenges.map((c) => c.toJson()).toList(),
      }),
    );
  }
}

class _SavedChallengeFile {
  final Map<String, Challenge> challenges;
  final Set<String> seenSeedIds;

  /// The built-in list version this save was last brought up to; null for a
  /// save from before versions existed.
  final int? seedVersion;

  const _SavedChallengeFile({
    required this.challenges,
    required this.seenSeedIds,
    this.seedVersion,
  });
}

class _Seed {
  final int version;
  final Map<String, Challenge> challenges;

  const _Seed(this.version, this.challenges);
}
