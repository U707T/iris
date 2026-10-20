import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/purge_legacy_storage_types.dart';

class HistoryStore extends PersistentStore<HistoryState> {
  HistoryStore() : super(HistoryState());

  /// 最多保留的历史条数 (防止无限增长: 每个条目都会随整个 map 一起
  /// 序列化写盘, 不设上限时 save 会随观看历史越来越慢)。
  static const int maxEntries = 300;

  Progress? findById(String id) => state.history[id];

  Future<void> add(Progress progress) async {
    final history = {
      ...state.history,
      progress.file.getID(): progress,
    };

    if (history.length > maxEntries) {
      final entries = history.entries.toList()
        ..sort((a, b) => b.value.dateTime.compareTo(a.value.dateTime));
      history
        ..clear()
        ..addEntries(entries.take(maxEntries));
    }

    set(state.copyWith(history: history));
    await save(state);
  }

  Future<void> remove(Progress progress) async {
    set(state.copyWith(
        history: {...state.history}..remove(progress.file.getID())));
    await save(state);
  }

  Future<void> clear() async {
    set(state.copyWith(history: {}));
    await save(state);
  }

  @override
  Future<HistoryState?> load() async {
    logger('Loading HistoryState');
    try {
            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      String? historyState = await storage.read(key: 'history_state');
      if (historyState != null) {
        final data = sanitizeHistoryJson(json.decode(historyState));
        if (data != null) return HistoryState.fromJson(data);
      }
    } catch (e) {
      logger('Error loading HistoryState: $e');
    }
    return null;
  }

  @override
  Future<void> save(HistoryState state) async {
    try {
            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      await storage.write(
          key: 'history_state', value: json.encode(state.toJson()));
    } catch (e) {
      logger('Error saving HistoryState: $e');
    }
  }
}

HistoryStore useHistoryStore() => create(() => HistoryStore());
