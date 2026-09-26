import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'challenge_model.dart';

class ChallengeRepository {
  static const String seedAssetPath = 'assets/data/challenge.json';
  static const String editableFileName = 'challenge_editor.json';

  Future<Map<String, Challenge>> loadChallenges() async {
    final file = await _editableChallengeFile();
    final seedChallenges = _decodeChallenges(
      await rootBundle.loadString(seedAssetPath),
    );

    if (!await file.exists()) {
      await _writeChallengeFile(file, seedChallenges.values, seedChallenges.keys.toSet());
      return seedChallenges;
    }

    final saved = _decodeChallengeFile(await file.readAsString());
    final mergedChallenges = _mergeSeedDefaults(
      seedChallenges: seedChallenges,
      editableChallenges: saved.challenges,
      previouslySeenSeedIds: saved.seenSeedIds,
    );

    // Remember every seed id we've ever shown, so a challenge the user
    // deleted or renamed away from isn't re-added from the seed on a later
    // load just because its id is momentarily absent from the saved file.
    final updatedSeenSeedIds = {...saved.seenSeedIds, ...seedChallenges.keys};

    await _writeChallengeFile(file, mergedChallenges.values, updatedSeenSeedIds);
    return mergedChallenges;
  }

  Future<void> saveChallenges(Iterable<Challenge> challenges) async {
    final file = await _editableChallengeFile();
    final seenSeedIds = await file.exists()
        ? _decodeChallengeFile(await file.readAsString()).seenSeedIds
        : <String>{};
    await _writeChallengeFile(file, challenges, seenSeedIds);
  }

  /// Replaces the saved challenge data with [jsonText] if (and only if) it
  /// parses as a valid save file (either the current or legacy format).
  /// Returns whether the import succeeded; on failure, existing data is
  /// left untouched.
  Future<bool> importFromJson(String jsonText) async {
    try {
      _decodeChallengeFile(jsonText);
    } catch (_) {
      return false;
    }

    final file = await _editableChallengeFile();
    await file.writeAsString(jsonText);
    return true;
  }

  Future<void> resetEditableChallenges() async {
    final file = await _editableChallengeFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> editableFilePath() async {
    return (await _editableChallengeFile()).path;
  }

  Future<File> _editableChallengeFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$editableFileName');
  }

  Map<String, Challenge> _decodeChallenges(String jsonText) {
    final decodedData = jsonDecode(jsonText) as List<dynamic>;
    return {
      for (final item in decodedData)
        (item as Map<String, dynamic>)['id'] as String: Challenge.fromJson(
          item,
        ),
    };
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
      challenges: {
        for (final item in challengesJson)
          (item as Map<String, dynamic>)['id'] as String: Challenge.fromJson(
            item,
          ),
      },
      seenSeedIds: {
        for (final id in (map['seenSeedIds'] as List<dynamic>? ?? const []))
          id as String,
      },
    );
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
    File file,
    Iterable<Challenge> challenges,
    Set<String> seenSeedIds,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'seenSeedIds': seenSeedIds.toList(),
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
