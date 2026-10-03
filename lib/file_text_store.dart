import 'dart:io';

import 'text_store.dart';

/// [TextStore] backed by real files in one directory (iOS, Android,
/// desktop). Writes go through a `.tmp` file and an atomic rename, so an
/// interrupted write never corrupts the existing save.
class FileTextStore implements TextStore {
  final Future<String> Function() directory;

  const FileTextStore({required this.directory});

  /// Full path of [name]'s file. Used by tests that need to poke the file
  /// directly (e.g. to plant a legacy-format save).
  Future<String> pathFor(String name) async => '${await directory()}/$name';

  Future<File> _file(String name) async => File(await pathFor(name));

  @override
  Future<String?> read(String name) async {
    final file = await _file(name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String name, String text) async {
    final destination = await _file(name);
    final temporaryFile = File('${destination.path}.tmp');
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    await temporaryFile.writeAsString(text, flush: true);
    await temporaryFile.rename(destination.path);
  }

  @override
  Future<bool> exists(String name) async => (await _file(name)).exists();

  @override
  Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
