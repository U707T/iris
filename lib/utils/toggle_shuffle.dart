import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// 切换随机播放 (控制栏按钮 / Ctrl + X 共用)。
///
/// - 打开: 立刻**重新洗牌**出一份新的随机顺序 (当前这条排在最前),
///   之后按这份顺序把整个列表播完;
/// - 关闭: 恢复文件本来的顺序 (按队列下标升序)。
///
/// 每次开 / 关都会重新洗牌, 所以反复开关不会回到上一次那份顺序。
Future<void> toggleShuffle({bool? value}) async {
  final appStore = useAppStore();
  final playQueueStore = usePlayQueueStore();
  final next = value ?? !appStore.state.shuffle;
  if (next) {
    await playQueueStore.shuffle();
  } else {
    await playQueueStore.sort();
  }
  await appStore.updateShuffle(next);
}
