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
      await _writeChallenges(file, seedChallenges.values);
      return seedChallenges;
    }

    final editableChallenges = _decodeChallenges(await file.readAsString());
    final mergedChallenges = _mergeSeedDefaults(
      seedChallenges: seedChallenges,
      editableChallenges: editableChallenges,
    );

    await _writeChallenges(file, mergedChallenges.values);
    return mergedChallenges;
  }

  Future<void> saveChallenges(Iterable<Challenge> challenges) async {
    final file = await _editableChallengeFile();
    await _writeChallenges(file, challenges);
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

  Map<String, Challenge> _mergeSeedDefaults({
    required Map<String, Challenge> seedChallenges,
    required Map<String, Challenge> editableChallenges,
  }) {
    final merged = Map<String, Challenge>.from(editableChallenges);

    for (final seedEntry in seedChallenges.entries) {
      final editableChallenge = merged[seedEntry.key];
      if (editableChallenge == null) {
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

  Future<void> _writeChallenges(
    File file,
    Iterable<Challenge> challenges,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(challenges.map((c) => c.toJson()).toList()),
    );
  }
}
