import 'dart:async';

import 'package:iris/models/file.dart';
import 'package:iris/pages/player/player_handoff.dart';
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
  // 交接: 普通模式的播放器是异步销毁的 (要等内部初始化 / 锁), 先显式静音,
  // 否则操作过快时它会和短视频池同时出声。
  // 仅在"确实是从普通模式进入"时静音 —— 重复调用 (连点 / 双击) 时当前
  // 注册的已经是短视频池, 静音会把刚进入的短视频也停掉。
  if (!usePlayerUiStore().state.isShortVideoMode) {
    unawaited(silenceActivePlayer());
  }
  usePlayerUiStore().updateShortVideoMode(true);
}

/// 退出短视频模式
void exitShortVideoMode() {
  final uiStore = usePlayerUiStore();
  // 交接: 先让短视频池全部静音, 再切回普通模式 (普通模式会重新装载并播放)。
  // 同样只在"确实处于短视频模式"时静音, 避免重复调用时停掉刚挂载的普通播放器。
  if (uiStore.state.isShortVideoMode) {
    unawaited(silenceActivePlayer());
  }
  uiStore.updateShortVideoMode(false);
  uiStore.updateIsSeeking(false);
  uiStore.updateIsShowProgress(false);
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
