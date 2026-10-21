import 'dart:async';
import 'dart:convert';

import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/utils/logger.dart';

typedef JsonFromMap<T> = T Function(Map<String, dynamic> json);
typedef JsonToMap<T> = Map<String, dynamic> Function(T value);
typedef JsonMigration = Map<String, dynamic> Function(Map<String, dynamic>);

/// 带 schema 版本、原子替换和写入合并的 JSON 持久化。
///
/// 落盘格式：
/// ```json
/// {"schema": 1, "data": {...}}
/// ```
/// 没有 `schema` 的旧裸 JSON 会按 v1 读取，并在下一次保存时升级。
class JsonPersistence<T> {
  JsonPersistence({
    required this.store,
    required this.key,
    required this.fromJson,
    required this.toJson,
    this.schemaVersion = 1,
    this.migrations = const {},
    this.legacyStore,
    this.legacyKey,
    this.onLoaded,
  });

  final KeyValueStore store;
  final String key;
  final JsonFromMap<T> fromJson;
  final JsonToMap<T> toJson;
  final int schemaVersion;
  final Map<int, JsonMigration> migrations;

  /// 旧版本使用另一个后端（例如从 secure storage 迁到文件）时读取一次。
  final KeyValueStore? legacyStore;
  final String? legacyKey;

  /// 解码后的补丁，例如 `autoPlay` 要按启动参数覆盖。
  final T Function(T value)? onLoaded;

  String? _pending;
  bool _writing = false;
  Completer<void>? _waiters;

  /// 最近一次写入错误（不向 UI 抛，避免 unawaited save 变成未捕获异常）。
  Object? lastSaveError;

  Future<T?> load() async {
    try {
      var raw = await store.read(key);

      if (raw == null && legacyStore != null && legacyKey != null) {
        final legacyRaw = await legacyStore!.read(legacyKey!);
        if (legacyRaw != null) {
          final value = _decode(legacyRaw);
          // 先确认新后端写成功，再删旧数据；中途失败旧数据仍在。
          await store.write(key, _encode(value));
          try {
            await legacyStore!.delete(legacyKey!);
          } catch (e) {
            logger('Legacy data delete failed ($legacyKey): $e');
          }
          return value;
        }
      }

      if (raw == null) return null;
      return _decode(raw);
    } catch (e) {
      logger('Load $key failed: $e');
      rethrow;
    }
  }

  Future<void> save(T state) {
    String encoded;
    try {
      encoded = _encode(state);
    } catch (e) {
      lastSaveError = e;
      logger('Encode $key failed: $e');
      return Future<void>.value();
    }

    _pending = encoded;
    final completer = _waiters ??= Completer<void>();
    if (!_writing) {
      unawaited(_drain());
    }
    return completer.future;
  }

  /// 合并写入：同一时刻只有一个后端写操作，排队期间只保留最新快照。
  Future<void> _drain() async {
    _writing = true;
    try {
      while (_pending != null) {
        final value = _pending!;
        _pending = null;
        try {
          await store.write(key, value);
        } catch (e) {
          lastSaveError = e;
          // 不中断：后面可能已经排了更新的快照。
          logger('Save $key failed: $e');
        }
      }
    } finally {
      _writing = false;
      final waiters = _waiters;
      _waiters = null;
      waiters?.complete();
    }

    if (_pending != null && !_writing) {
      unawaited(_drain());
    }
  }

  T _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Persisted state is not a JSON object');
    }

    final map = Map<String, dynamic>.from(decoded);
    Map<String, dynamic> data;
    int version;

    if (!map.containsKey('schema')) {
      // v1 之前的裸 JSON: 按 v1 处理, 后续版本仍需走迁移链。
      version = 1;
      data = map;
    } else {
      final rawVersion = map['schema'];
      if (rawVersion is! int) {
        throw const FormatException('Invalid schema version');
      }
      if (rawVersion > schemaVersion) {
        throw StateError(
          'Persisted $key schema $rawVersion is newer than $schemaVersion',
        );
      }
      final rawData = map['data'];
      if (rawData is! Map) {
        throw const FormatException('Missing schema data');
      }
      version = rawVersion;
      data = Map<String, dynamic>.from(rawData);
    }

    for (var v = version; v < schemaVersion; v++) {
      final migration = migrations[v];
      if (migration == null) {
        throw StateError('No migration from $key schema $v');
      }
      data = migration(data);
    }

    final value = fromJson(data);
    return onLoaded?.call(value) ?? value;
  }

  String _encode(T value) => jsonEncode({
        'schema': schemaVersion,
        'data': toJson(value),
      });
}
