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
    final jsonText = await _readOrCreateEditableJson(file);
    return _decodeChallenges(jsonText);
  }

  Future<void> saveChallenges(Iterable<Challenge> challenges) async {
    final file = await _editableChallengeFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(challenges.map((c) => c.toJson()).toList()),
    );
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

  Future<String> _readOrCreateEditableJson(File file) async {
    if (await file.exists()) {
      return file.readAsString();
    }

    final seedJson = await rootBundle.loadString(seedAssetPath);
    await file.writeAsString(seedJson);
    return seedJson;
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
}
