import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iris/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore._();
  static final SecureKeyValueStore instance = SecureKeyValueStore._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

typedef AppDirectoryProvider = Future<Directory> Function();
typedef RenameFile = Future<File> Function(File file, String destination);

/// A flushed temporary file plus a recoverable copy of the last committed file.
/// Windows may require removing the destination before rename. The backup must
/// survive that gap, including a process exit or a failed second rename.
class FileKeyValueStore implements KeyValueStore {
  FileKeyValueStore({
    AppDirectoryProvider? directoryProvider,
    RenameFile? rename,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _rename = rename ?? ((file, destination) => file.rename(destination));

  final AppDirectoryProvider _directoryProvider;
  final RenameFile _rename;
  Future<Directory>? _directoryFuture;

  Future<Directory> _directory() =>
      _directoryFuture ??= _directoryProvider().then((directory) async {
        await directory.create(recursive: true);
        return directory;
      });

  Future<File> _file(String key) async {
    final directory = await _directory();
    return File(p.join(directory.path, '${p.basename(key)}.json'));
  }

  @override
  Future<String?> read(String key) async {
    final file = await _file(key);
    if (await file.exists()) return file.readAsString();
    final backup = File('${file.path}.bak');
    if (await backup.exists()) return backup.readAsString();
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temp.writeAsString(value, flush: true);
    final hadFile = await file.exists();
    if (hadFile) {
      // Copy failure leaves the original in place and aborts the replacement.
      await file.copy(backup.path);
    }
    try {
      await _rename(temp, file.path);
    } on FileSystemException {
      if (!hadFile) rethrow;
      // The old value is already safe in .bak before deleting a destination.
      // If the second rename fails, read() uses .bak; copying it back here
      // could itself fail halfway and leave a partial primary file.
      if (await file.exists()) await file.delete();
      await _rename(temp, file.path);
    }
    if (await backup.exists()) {
      try {
        await backup.delete();
      } catch (e) {
        logger('Failed to remove obsolete state backup: $e');
      }
    }
  }

  @override
  Future<void> delete(String key) async {
    final file = await _file(key);
    // Remove backup first so an interrupted delete cannot resurrect old state.
    for (final candidate in [
      File('${file.path}.bak'),
      File('${file.path}.tmp'),
      file,
    ]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }
}
