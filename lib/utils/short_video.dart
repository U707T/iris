import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';

/// 短视频模式: 从播放队列中过滤出视频条目 (跳过音频)
List<PlayQueueItem> getVideoItems(List<PlayQueueItem> playQueue) =>
    playQueue.where((item) => item.file.type == ContentType.video).toList();

/// 选择进入短视频模式时的起始视频:
/// 优先当前项本身 (视频); 否则取其后的第一条视频; 再否则取最后一条。
int pickShortVideoIndex(List<PlayQueueItem> items, int playQueueIndex) {
  if (items.isEmpty) return -1;
  final exact = items.indexWhere((item) => item.index == playQueueIndex);
  if (exact >= 0) return exact;
  final next = items.indexWhere((item) => item.index > playQueueIndex);
  if (next >= 0) return next;
  return items.length - 1;
}

/// 进入短视频模式: 定位到起始视频并切换界面
void enterShortVideoMode() {
  final playQueueStore = usePlayQueueStore();
  final items = getVideoItems(playQueueStore.state.playQueue);
  if (items.isEmpty) return;

  final target = pickShortVideoIndex(items, playQueueStore.state.currentIndex);
  if (target >= 0 && items[target].index != playQueueStore.state.currentIndex) {
    playQueueStore.updateCurrentIndex(items[target].index);
  }

  // 短视频模式内划到哪条播哪条
  useAppStore().updateAutoPlay(true);
  usePlayerUiStore().updateIsShowControl(false);
  usePlayerUiStore().updateIsShowProgress(false);
  usePlayerUiStore().updateShortVideoMode(true);
}

/// 退出短视频模式
void exitShortVideoMode() {
  usePlayerUiStore().updateShortVideoMode(false);
  usePlayerUiStore().updateIsSeeking(false);
  usePlayerUiStore().updateIsShowProgress(false);
}

/// 在短视频模式内切换到上一条 / 下一条视频 (跳过音频)
Future<void> moveShortVideoBy(int delta) async {
  final playQueueStore = usePlayQueueStore();
  final items = getVideoItems(playQueueStore.state.playQueue);
  final current = items.indexWhere(
      (item) => item.index == playQueueStore.state.currentIndex);
  if (current < 0) return;

  final next = (current + delta).clamp(0, items.length - 1);
  if (next == current) return;
  await playQueueStore.updateCurrentIndex(items[next].index);
}
