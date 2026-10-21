import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/store/state_decoders.dart';

class HistoryStore extends PersistentStore<HistoryState> {
  HistoryStore()
      : super(
          HistoryState(),
          JsonPersistence<HistoryState>(
            store: FileKeyValueStore(),
            legacyStore: SecureKeyValueStore.instance,
            legacyKey: 'history_state',
            key: 'history_state',
            fromJson: decodeHistoryState,
            toJson: (state) => state.toJson(),
          ),
        );

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
  Future<HistoryState?> load() => loadPersisted();
}

HistoryStore useHistoryStore() => create(() => HistoryStore());
