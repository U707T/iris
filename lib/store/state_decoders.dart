import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/models/store/storage_state.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/purge_legacy_storage_types.dart';

/// 逐条解码播放队列：未知枚举 / 坏条目只丢自己，不连坐整份队列。
PlayQueueState decodePlayQueueState(Map<String, dynamic> json) {
  // 先处理已知的 FTP 旧数据（保留原来的 currentIndex 重映射规则）。
  final cleaned = sanitizePlayQueueJson(json) ?? const <String, dynamic>{};
  final rawQueue = cleaned['playQueue'];

  final items = <PlayQueueItem>[];
  if (rawQueue is List) {
    for (final entry in rawQueue) {
      if (entry is! Map) continue;
      try {
        items.add(PlayQueueItem.fromJson(Map<String, dynamic>.from(entry)));
      } catch (e) {
        logger('Skipping invalid play queue entry: $e');
      }
    }
  }

  final requested =
      cleaned['currentIndex'] is int ? cleaned['currentIndex'] as int : 0;
  final int currentIndex;
  if (items.isEmpty) {
    currentIndex = 0;
  } else if (requested == -1 ||
      items.any((item) => item.index == requested)) {
    // -1 是"停止"态，不要凭空指到第一条
    currentIndex = requested;
  } else {
    currentIndex = items.first.index;
  }

  return PlayQueueState(playQueue: items, currentIndex: currentIndex);
}

/// 逐条解码历史：一条坏记录只丢一条。
HistoryState decodeHistoryState(Map<String, dynamic> json) {
  final cleaned = sanitizeHistoryJson(json) ?? const <String, dynamic>{};
  final rawHistory = cleaned['history'];
  final history = <String, Progress>{};

  if (rawHistory is Map) {
    rawHistory.forEach((key, value) {
      if (value is! Map) return;
      try {
        history['$key'] = Progress.fromJson(Map<String, dynamic>.from(value));
      } catch (e) {
        logger('Skipping invalid history entry $key: $e');
      }
    });
  }

  return HistoryState(history: history);
}

/// 逐条解码存储：未知 storage type（例如已移除的 FTP）或坏条目只丢自己，
/// 指向被丢存储的收藏 / 当前目录一并清理。
StorageState decodeStorageState(Map<String, dynamic> json) {
  final storages = <Storage>[];
  final rawStorages = json['storages'];
  if (rawStorages is List) {
    for (final entry in rawStorages) {
      if (entry is! Map) continue;
      try {
        storages.add(Storage.fromJson(Map<String, dynamic>.from(entry)));
      } catch (e) {
        logger('Skipping invalid storage entry: $e');
      }
    }
  }

  final storageIds = storages.map((storage) => storage.id).toSet();
  final favorites = <Favorite>[];
  final rawFavorites = json['favorites'];
  if (rawFavorites is List) {
    for (final entry in rawFavorites) {
      if (entry is! Map) continue;
      try {
        final favorite =
            Favorite.fromJson(Map<String, dynamic>.from(entry));
        // localStorageId 是运行时发现的本地磁盘，不在持久化 storages 里。
        if (favorite.storageId == localStorageId ||
            storageIds.contains(favorite.storageId)) {
          favorites.add(favorite);
        }
      } catch (e) {
        logger('Skipping invalid favorite entry: $e');
      }
    }
  }

  Storage? currentStorage;
  final rawCurrent = json['currentStorage'];
  if (rawCurrent is Map) {
    try {
      currentStorage =
          Storage.fromJson(Map<String, dynamic>.from(rawCurrent));
    } catch (e) {
      logger('Skipping invalid current storage: $e');
    }
  }

  final rawPath = json['currentPath'];
  final currentPath = rawPath is List
      ? rawPath.whereType<String>().toList()
      : const <String>[];

  return StorageState(
    storages: storages,
    favorites: favorites,
    currentStorage: currentStorage,
    currentPath: currentPath,
  );
}
