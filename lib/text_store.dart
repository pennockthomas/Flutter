import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_text_store.dart';

/// Where [ChallengeRepository] keeps its named blobs of JSON text: the save
/// file, and the one pre-import backup. Kept this small on purpose so the
/// app can run on platforms without a filesystem (the browser).
abstract class TextStore {
  Future<String?> read(String name);

  /// Replaces [name]'s contents. Must never leave a half-written value
  /// behind if interrupted.
  Future<void> write(String name, String text);

  Future<bool> exists(String name);

  Future<void> delete(String name);
}

/// The right store for the current platform: real files on iOS/Android/
/// desktop, browser local storage on the web.
TextStore createDefaultTextStore() {
  if (kIsWeb) return PrefsTextStore();
  return FileTextStore(
    directory: () async => (await getApplicationDocumentsDirectory()).path,
  );
}

/// Stores each blob as a `SharedPreferences` string — `localStorage` on the
/// web. A single `setString` is all-or-nothing, so no temp file is needed.
/// Bound to the browser profile, so it's per-browser and cleared with
/// "clear site data".
class PrefsTextStore implements TextStore {
  static const _keyPrefix = 'store.';

  String _key(String name) => '$_keyPrefix$name';

  @override
  Future<String?> read(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(name));
  }

  @override
  Future<void> write(String name, String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(name), text);
  }

  @override
  Future<bool> exists(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(name));
  }

  @override
  Future<void> delete(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(name));
  }
}
