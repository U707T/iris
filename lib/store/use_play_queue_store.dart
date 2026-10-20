import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/local.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/persistent_store.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/get_shuffle_play_queue.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/purge_legacy_storage_types.dart';
import 'package:iris/utils/queue_persistence.dart';
import 'package:saf_util/saf_util.dart';

class PlayQueueStore extends PersistentStore<PlayQueueState> {
  PlayQueueStore() : super(PlayQueueState());

  /// 统一落盘入口: update / updateCurrentIndex / add / remove 必须走同一判定,
  /// 否则会出现"索引被存了、队列却没存"的错位 (重启后索引指向不存在的条目)。
  ///
  /// 具体策略见 [persistedQueueState]: 混合队列只剔除 content:// 条目,
  /// 而不是整份丢弃; 删除路径额外要求"全 SAF 时写空", 免得刚删掉的条目复活。
  Future<void> _saveQueue({bool keepPreviousWhenEmpty = true}) async {
    final snapshot = persistedQueueState(
      state,
      keepPreviousWhenEmpty: keepPreviousWhenEmpty,
    );
    if (snapshot == null) return;
    await save(snapshot);
  }

  Future<void> update({
    required List<PlayQueueItem> playQueue,
    int? index,
  }) async {
    set(state.copyWith(
      playQueue: playQueue,
      currentIndex: index ?? state.currentIndex,
    ));
    await _saveQueue();
  }

  Future<void> updateCurrentIndex(int index) async {
    set(state.copyWith(currentIndex: index));
    await _saveQueue();
  }

  Future<void> add(List<FileItem> files) async {
    final int maxIndex = state.playQueue.isEmpty
        ? -1
        : state.playQueue.map((e) => e.index).reduce(max);
    final int startIndex = maxIndex + 1;

    final List<PlayQueueItem> playQueue = files
        .asMap()
        .entries
        .map((entry) =>
            PlayQueueItem(file: entry.value, index: startIndex + entry.key))
        .toList();

    set(state.copyWith(playQueue: [...state.playQueue, ...playQueue]));
    await _saveQueue();
  }

  Future<void> remove(PlayQueueItem item) async {
    if (state.playQueue.length <= 1) {
      set(state.copyWith(playQueue: [], currentIndex: 0));
    } else {
      final index = state.playQueue.indexOf(item);
      if (index < 0) return;
      if (state.playQueue[index].index == state.currentIndex) {
        if (index + 1 < state.playQueue.length) {
          set(state.copyWith(
            playQueue: [...state.playQueue]..remove(item),
            currentIndex: state.playQueue[index + 1].index,
          ));
        } else {
          set(state.copyWith(
            playQueue: [...state.playQueue]..remove(item),
            currentIndex: state.playQueue[index - 1].index,
          ));
        }
      } else {
        set(state.copyWith(
          playQueue: [...state.playQueue]..remove(item),
        ));
      }
    }
    // 删除路径不能"全 SAF 就保留旧快照": 否则刚删掉的本地条目会在重启后复活
    await _saveQueue(keepPreviousWhenEmpty: false);
  }

  Future<void> previous() async {
    // 空队列时 `.last` 会抛 StateError, 而这里是从按键回调 / 媒体键进来的,
    // 异常会直接冒到 UI 层 (删光队列后按 Ctrl + ← 就崩)。
    final playQueue = state.playQueue;
    if (playQueue.isEmpty) return;

    final int currentPlayIndex =
        playQueue.indexWhere((element) => element.index == state.currentIndex);
    if (currentPlayIndex <= 0) {
      await updateCurrentIndex(playQueue.last.index);
    } else {
      await updateCurrentIndex(playQueue[currentPlayIndex - 1].index);
    }
  }

  Future<void> next() async {
    final playQueue = state.playQueue;
    if (playQueue.isEmpty) return;

    final int currentPlayIndex =
        playQueue.indexWhere((element) => element.index == state.currentIndex);
    if (currentPlayIndex >= playQueue.length - 1) {
      await updateCurrentIndex(playQueue.first.index);
    } else {
      await updateCurrentIndex(playQueue[currentPlayIndex + 1].index);
    }
  }

  Future<void> shuffle() async => update(
        playQueue: getShufflePlayQueue(state.playQueue, state.currentIndex),
        index: state.currentIndex,
      );

  Future<void> sort() async => update(
        playQueue: [...state.playQueue]
          ..sort((a, b) => a.index.compareTo(b.index)),
        index: state.currentIndex,
      );

  @override
  Future<PlayQueueState?> load() async {
    logger('Loading PlayQueueState');
    try {
      if (isDesktop && globals.arguments.isNotEmpty) {
        String uri = globals.arguments[0];
        // 在线播放
        if (RegExp(r'^(http://|https://)').hasMatch(uri)) {
          final state = PlayQueueState(
            playQueue: [
              PlayQueueItem(
                file: FileItem(
                  name: uri,
                  uri: uri,
                ),
                index: 0,
              )
            ],
            currentIndex: 0,
          );
          // 显式打开 (命令行 / Intent): 标记给 AppState.load 用, 避免
          // 两个 store 的加载顺序把 autoPlay 冲掉。见 globals.autoPlayOnLaunch。
          globals.autoPlayOnLaunch = true;
          await useAppStore().updateAutoPlay(true);
          await save(state);
          return state;
        }

        // 本地播放
        final filePath = uri;
        if (isMediaFile(filePath)) {
          final state = await getLocalPlayQueue(filePath);
          if (state != null && state.playQueue.isNotEmpty) {
            // 显式打开 (命令行 / Intent): 标记给 AppState.load 用, 避免
            // 两个 store 的加载顺序把 autoPlay 冲掉。见 globals.autoPlayOnLaunch。
            globals.autoPlayOnLaunch = true;
            await useAppStore().updateAutoPlay(true);
            await save(state);
            return state;
          }
        }
      }

      final uri = globals.initUri;

      // Android
      if (uri != null && Platform.isAndroid) {
        final file = await SafUtil().documentFileFromUri(uri, false);
        if (file != null) {
          // 显式打开 (命令行 / Intent): 标记给 AppState.load 用, 避免
          // 两个 store 的加载顺序把 autoPlay 冲掉。见 globals.autoPlayOnLaunch。
          globals.autoPlayOnLaunch = true;
          await useAppStore().updateAutoPlay(true);
          return PlayQueueState(
            playQueue: [
              PlayQueueItem(
                file: FileItem(
                  name: file.name,
                  uri: file.uri,
                  size: file.length,
                ),
                index: 0,
              ),
            ],
            currentIndex: 0,
          );
        }
      }

            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      String? appState = await storage.read(key: 'playQueue_state');
      if (appState != null) {
        final data = sanitizePlayQueueJson(json.decode(appState));
        if (data != null) return PlayQueueState.fromJson(data);
      }
    } catch (e) {
      logger('Error loading PlayQueueState: $e');
    }
    return null;
  }

  @override
  Future<void> save(PlayQueueState state) async {
    try {
            final storage = FlutterSecureStorage(aOptions: const AndroidOptions());

      await storage.write(
          key: 'playQueue_state', value: json.encode(state.toJson()));
    } catch (e) {
      logger('Error saving PlayQueueState: $e');
    }
  }
}

PlayQueueStore usePlayQueueStore() => create(() => PlayQueueStore());
