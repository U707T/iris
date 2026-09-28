import 'dart:math';
import 'package:iris/models/file.dart';

/// 生成一份新的随机播放顺序 (洗牌)。
///
/// 返回的是播放队列的一份**完整排列**: 所有条目都在, 不重复, 不丢失,
/// 并且把当前播放的这条 ([index]) 放在最前面 —— 这样洗牌后接着往下播
/// 就是"当前视频 → 其余视频的随机顺序"。
///
/// [index] 在队列里找不到时 (例如队列刚被替换) 直接整体洗牌, 不丢条。
List<PlayQueueItem> getShufflePlayQueue(
    List<PlayQueueItem> playQueue, int index) {
  if (playQueue.isEmpty) return [];

  final int seed = DateTime.now().millisecondsSinceEpoch;
  final Random random = Random(seed);
  final List<PlayQueueItem> shuffledList = [...playQueue];

  final int currentItemIndex =
      shuffledList.indexWhere((element) => element.index == index);

  if (currentItemIndex == -1) {
    return shuffledList;
  }

  final PlayQueueItem currentItem = shuffledList.removeAt(currentItemIndex);
  for (int i = shuffledList.length - 1; i > 0; i--) {
    final int j = random.nextInt(i + 1);
    final temp = shuffledList[i];
    shuffledList[i] = shuffledList[j];
    shuffledList[j] = temp;
  }

  shuffledList.insert(0, currentItem);

  return shuffledList;
}
