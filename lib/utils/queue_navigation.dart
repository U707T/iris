import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart';

/// 一条播完之后要切到的下一条 —— 返回的是**播放队列内的下标**
/// (不是 [PlayQueueItem.index])。
///
/// 返回 null 表示原地不动 (不自动连播)。以下情况都必须返回 null 而不是硬取下标:
/// - 队列为空 (删掉最后一条后播完, `playQueue[0]` 会越界);
/// - 当前项已不在队列里 (`currentPlayIndex < 0`, 例如停止 / 刚被删除);
/// - 单条循环, 或播到最后一条且没开列表循环。
///
/// 主播放界面 (media_kit / fvp) 共用这一份实现, 避免两处各写一套、
/// 修了一边漏一边。
int? nextIndexOnCompleted({
  required List<PlayQueueItem> playQueue,
  required int currentPlayIndex,
  required Repeat repeat,
}) {
  if (playQueue.isEmpty) return null;
  if (repeat == Repeat.one) return null;
  if (currentPlayIndex < 0 || currentPlayIndex >= playQueue.length) return null;

  if (currentPlayIndex == playQueue.length - 1) {
    return repeat == Repeat.all ? 0 : null;
  }
  return currentPlayIndex + 1;
}
