import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/logger.dart';

/// 启动时重新洗牌: 随机播放开着的话, 每次打开应用都换一份新的随机顺序。
///
/// 播放队列的顺序是持久化的, 不重洗的话每次启动沿用的都是上次那份顺序
/// (用户期望的是"每次开启应用都重新随机一下")。两个 store 都是异步加载的,
/// 因此这里等它们加载完 (带超时兜底) 再判断, 且只做一次。
void useShuffleOnLaunch() {
  final handled = useRef(false);

  useEffect(() {
    var alive = true;
    unawaited(() async {
      final appStore = useAppStore();
      final playQueueStore = usePlayQueueStore();

      var waited = 0;
      while (alive &&
          (!appStore.isLoaded || !playQueueStore.isLoaded) &&
          waited < 3000) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        waited += 50;
      }
      if (!alive || handled.value) return;
      handled.value = true;
      // 随机播放没开 / 队列太短就不动它
      if (!appStore.state.shuffle || playQueueStore.state.playQueue.length < 2) {
        return;
      }
      logger('Shuffle on launch');
      await playQueueStore.shuffle();
    }());
    return () => alive = false;
  }, const []);
}
