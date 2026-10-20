import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/queue_navigation.dart';
import 'package:media_kit/media_kit.dart';

/// 一条播完后的自动连播。
///
/// "下一条是谁"的规则收在 [nextIndexOnCompleted]（空队列 / 当前项已删除 /
/// 单条循环 / 列表循环都有测试），这里只负责执行。
void useAutoNext({
  required Player player,
  required List<PlayQueueItem> playQueue,
  required int currentPlayIndex,
  required Repeat repeat,
  required bool completed,
}) {
  useEffect(() {
    () async {
      if (!completed) return;
      // 队列可能已经被清空 / 当前项已被删除: 交给共用逻辑判空, 不要直接取下标
      final next = nextIndexOnCompleted(
        playQueue: playQueue,
        currentPlayIndex: currentPlayIndex,
        repeat: repeat,
      );
      if (next == null) return;
      if (next == currentPlayIndex) {
        // 单条队列 + 列表循环: 下标没变, 不会再触发装载, 手动回到开头重播
        await player.seek(Duration.zero);
        await player.play();
        return;
      }
      await usePlayQueueStore().updateCurrentIndex(playQueue[next].index);
    }();
    return null;
  }, [completed, repeat]);
}
