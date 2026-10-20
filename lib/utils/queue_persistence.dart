import 'package:collection/collection.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';

/// content:// (SAF) URI 是会话级授权: 重启后不保证还能读,
/// 因此不能原样写进持久化队列。
bool isSessionOnlyUri(String uri) => uri.startsWith('content://');

/// 返回"可以落盘"的队列状态; 返回 null 表示本次不要写盘。
///
/// - 没有 content:// 条目: 原样返回 (不做无谓拷贝);
/// - 真·空队列: 照常存 (用户确实清空了队列);
/// - 全是 content:// 条目:
///   - [keepPreviousWhenEmpty] 为 true (默认): 返回 null, 保留上一次的持久化快照 ——
///     否则"用 SAF 打开一个视频"会把用户原来的本地队列擦成空;
///   - 为 false (删除路径): 返回空队列快照, 避免刚删掉的本地条目在重启后复活;
/// - 混合队列: 只剔除重启后打不开的条目, currentIndex 映射到最近的存活条目
///   (当前条被剔除 -> 下一条 -> 上一条)。
///
/// 旧实现是"只要队列里有任意 content:// 就整份不存", 混合队列下
/// 增删 / 换序 / 切集全部丢失, 重启后看起来"队列丢了一半"。
PlayQueueState? persistedQueueState(
  PlayQueueState state, {
  bool keepPreviousWhenEmpty = true,
}) {
  final items = state.playQueue;
  if (items.isEmpty) return state;

  final restorable =
      items.where((item) => !isSessionOnlyUri(item.file.uri)).toList();
  if (restorable.length == items.length) return state;
  if (restorable.isEmpty) {
    return keepPreviousWhenEmpty ? null : state.copyWith(playQueue: const []);
  }

  return state.copyWith(
    playQueue: restorable,
    currentIndex: _remapCurrentIndex(items, restorable, state.currentIndex),
  );
}

int _remapCurrentIndex(
  List<PlayQueueItem> all,
  List<PlayQueueItem> restorable,
  int currentIndex,
) {
  // 停止态 (-1) / 索引本来就失效: 原样保留, 别凭空指到某一条
  if (!all.any((item) => item.index == currentIndex)) return currentIndex;
  if (restorable.any((item) => item.index == currentIndex)) return currentIndex;

  final next = restorable.firstWhereOrNull((item) => item.index > currentIndex);
  return next?.index ?? restorable.last.index;
}
