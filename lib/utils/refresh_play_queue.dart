import 'dart:math';

import 'package:collection/collection.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/files_sort.dart';
import 'package:iris/utils/logger.dart';

/// 播放项所在目录 (`path` 的最后一段是文件名)。
///
/// 单文件 / 在线链接 / picker 打开的文件没有目录段, 返回空列表 —— 调用方据此
/// 放弃回扫, 而不是拿 `path[0]` 当目录去扫整个根分区。
List<String> folderOfPlayQueueItem(FileItem file) =>
    file.path.length > 1 ? file.path.sublist(0, file.path.length - 1) : const [];

/// 用最新目录列表更新队列成员 (**纯函数**, 便于单测)。
///
/// 三个动作, 都是「按 uri 认文件」:
/// - **保留**: 还在目录里的条目原样留下 —— 顺序、`index`、连 `FileItem` 实例
///   都不换。当前项的实例没变, `usePlayerEngine` 的 `useEffect([file])` 就不会
///   重新 open, 刷新不会打断正在播的片子;
/// - **移除**: 目录里已经没有的条目;
/// - **追加**: 目录里新出现的条目排到末尾, `index` 从原来的最大值往上发。
///
/// 返回 null 表示「一个现有条目都对不上」(整目录被删 / 换了盘), 这时不该把
/// 队列清空 —— 正在播的东西还在, 队列没了反而更糟。
PlayQueueState? mergeQueueWithListed({
  required PlayQueueState state,
  required List<FileItem> listed,
}) {
  final items = state.playQueue;
  if (items.isEmpty) return null;

  final listedUris = {for (final file in listed) file.uri};

  final kept = <PlayQueueItem>[];
  for (final item in items) {
    if (listedUris.contains(item.file.uri)) kept.add(item);
  }
  if (kept.isEmpty) return null;

  final keptUris = {for (final item in kept) item.file.uri};
  var nextIndex = items.map((item) => item.index).reduce(max) + 1;

  final added = <PlayQueueItem>[];
  for (final file in listed) {
    if (keptUris.contains(file.uri)) continue;
    added.add(PlayQueueItem(file: file, index: nextIndex++));
  }

  final queue = [...kept, ...added];
  return state.copyWith(
    playQueue: queue,
    currentIndex: _currentIndexAfterMerge(
      oldItems: items,
      newItems: queue,
      currentIndex: state.currentIndex,
    ),
  );
}

/// 刷新后当前项应该落在哪个 index 上。
///
/// 当前项还在队列里 (绝大多数情况) 就原样返回 —— 换 index 等于告诉播放器
/// "换片了", 会重新 open。当前项已被删除时退到原位置附近; 停止态 (-1) 保持
/// 停止, 不凭空指到某一条。
int _currentIndexAfterMerge({
  required List<PlayQueueItem> oldItems,
  required List<PlayQueueItem> newItems,
  required int currentIndex,
}) {
  if (newItems.any((item) => item.index == currentIndex)) return currentIndex;

  final oldPosition = oldItems.indexWhere((item) => item.index == currentIndex);
  if (oldPosition < 0) return currentIndex;
  return newItems[min(oldPosition, newItems.length - 1)].index;
}

/// 回扫当前播放项所在目录, 用最新内容更新播放队列 (控制栏「刷新播放列表」)。
///
/// 返回刷新后的队列长度; null 表示**没有改动队列**:
/// 队列为空 / 找不到可回扫的目录 (在线链接、单个 SAF 文件) / 目录读取失败 /
/// 目录里一个媒体文件都不剩。调用方据此给出成功或失败的反馈。
Future<int?> refreshPlayQueue() async {
  final store = usePlayQueueStore();
  final state = store.state;

  final current = state.playQueue
          .firstWhereOrNull((item) => item.index == state.currentIndex)
          ?.file ??
      state.playQueue.firstOrNull?.file;
  if (current == null) return null;

  final folder = folderOfPlayQueueItem(current);
  if (folder.isEmpty) return null;

  final storage = _storageFor(current);
  if (storage == null) return null;

  final List<FileItem> listed;
  try {
    listed = await storage.getFiles(folder);
  } catch (e) {
    // 目录被拔掉 / 网络盘断了 / SAF 授权过期: 报错但不动现有队列
    logger('Refresh play queue failed: $e');
    return null;
  }

  // 跟文件浏览器同一套排序, 新追加的条目才不会插得七零八落
  final appState = useAppStore().state;
  final media = filesSort(
    files: [
      for (final file in listed)
        if (file.type == ContentType.video || file.type == ContentType.audio)
          file,
    ],
    sortBy: appState.sortBy,
    sortOrder: appState.sortOrder,
    folderFirst: appState.folderFirst,
  );

  final latest = store.state;
  final merged = mergeQueueWithListed(
    // 用扫描结束时的队列状态做合并, 而不是开头那份快照: 大目录回扫要几百
    // 毫秒, 期间用户可能删条目 / 切集, 拿旧快照覆盖等于把这些操作抹掉。
    state: latest,
    listed: media,
  );
  if (merged == null) return null;

  // 目录内容没变就别写: `update` 会落一次盘并触发整棵控制栏重建,
  // 用户只是手贱点了一下刷新不该有这些动静。
  if (!_sameQueue(merged.playQueue, latest.playQueue) ||
      merged.currentIndex != latest.currentIndex) {
    await store.update(
      playQueue: merged.playQueue,
      index: merged.currentIndex,
    );
  }
  return merged.playQueue.length;
}

/// 两份队列是不是"同一条不差": 顺序、`index`、`FileItem` 实例都一样。
///
/// 用 `identical` 而不是 `==` 才符合这里的语义 —— 刷新保留的就是原来的
/// 实例, 换了实例本身就意味着播放器要重新 open。
bool _sameQueue(List<PlayQueueItem> a, List<PlayQueueItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index || !identical(a[i].file, b[i].file)) {
      return false;
    }
  }
  return true;
}

/// 队列条目对应的存储: 优先查已配置的存储, 查不到就按本地路径 / SAF 兜底。
///
/// picker、拖放、命令行打开的文件 `storageId` 都是空的, 但 `path[0]` 一定是
/// 根 (本地磁盘或 `content://` 目录), `Storage.getFiles` 自己会按它分派。
Storage? _storageFor(FileItem file) {
  final known = useStorageStore().findById(file.storageId);
  if (known != null) return known;
  if (file.path.isEmpty) return null;

  return LocalStorage(
    type: StorageType.internal,
    name: file.path.first,
    basePath: [file.path.first],
  );
}
