import 'dart:async';

import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/utils/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_zustand/flutter_zustand.dart';

abstract class PersistentStore<T> extends Store<T> {
  PersistentStore(super.initialState, this.persistence) {
    _init();
  }

  @protected
  final JsonPersistence<T> persistence;

  final Completer<void> _ready = Completer<void>();
  bool _isLoaded = false;
  Object? _loadError;

  /// Whether the persisted state has been loaded (successfully or not).
  bool get isLoaded => _isLoaded;

  /// 加载失败原因；null 表示成功或 key 不存在。
  Object? get loadError => _loadError;

  /// 加载结束（成功 / 不存在 / 失败都会完成）。启动时等待它，避免用户操作
  /// 和迟到的 `set(loaded)` 打架。
  Future<void> get ready => _ready.future;

  Future<void> _init() async {
    try {
      final loaded = await load();
      if (loaded != null) {
        set(loaded);
      }
    } catch (e) {
      // 读失败 != 没有数据。记录错误并拒绝后续覆盖写入。
      _loadError = e;
      logger('Failed to load $runtimeType: $e');
    } finally {
      _isLoaded = true;
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// 子类只负责"怎么从持久化数据变成状态"，失败必须抛出，
  /// 返回 null 仅表示真的没有持久化数据。
  Future<T?> load();

  @protected
  Future<T?> loadPersisted() => persistence.load();

  /// 默认保存入口：加载失败时宁可不写，也不要用默认值覆盖原文件。
  @mustCallSuper
  Future<void> save(T state) async {
    if (_loadError != null) {
      logger('Refusing to overwrite $runtimeType after a failed load');
      return;
    }
    await persistence.save(state);
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    await save(state);
    await super.dispose();
  }
}
