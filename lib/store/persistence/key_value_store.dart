import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iris/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 最小键值存储接口。
///
/// 约定：
/// - [read] 返回 null 表示 key 不存在；
/// - I/O / 解密 / 文件损坏一律抛异常，绝不能把失败伪装成"没有数据"。
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 加密存储：只放真正的敏感信息（WebDAV 凭据等）。
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore._();

  static final SecureKeyValueStore instance = SecureKeyValueStore._();

  static const FlutterSecureStorage _storage =
      FlutterSecureStorage(aOptions: AndroidOptions());

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

typedef AppDirectoryProvider = Future<Directory> Function();

/// 应用私有目录里的 JSON 文件。
///
/// 用临时文件 + rename 原子替换，避免写到一半崩溃留下半截 JSON。
/// 适合设置 / 队列 / 历史这类体积会增长、且不需要硬件加密的数据。
class FileKeyValueStore implements KeyValueStore {
  FileKeyValueStore({AppDirectoryProvider? directoryProvider})
      : _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  final AppDirectoryProvider _directoryProvider;
  Future<Directory>? _directoryFuture;

  Future<Directory> _directory() =>
      _directoryFuture ??= _directoryProvider().then((directory) async {
        await directory.create(recursive: true);
        return directory;
      });

  Future<File> _file(String key) async {
    final directory = await _directory();
    // key 只允许简单名字；basename 防止意外路径穿越。
    return File(p.join(directory.path, '${p.basename(key)}.json'));
  }

  @override
  Future<String?> read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);

    try {
      await temp.rename(file.path);
    } on FileSystemException {
      // Windows 的 rename 不保证覆盖已有文件。
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }

  @override
  Future<void> delete(String key) async {
    final file = await _file(key);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        logger('Failed to delete ${file.path}: $e');
      }
    }
  }
}
