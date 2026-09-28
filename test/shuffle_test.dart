import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/get_shuffle_play_queue.dart';
import 'package:iris/utils/toggle_shuffle.dart';

/// 随机播放机制测试:
/// - 洗牌结果是一份完整排列 (不丢条 / 不重复), 当前这条排在最前
/// - 打开随机: 立刻重新洗牌; 关闭随机: 恢复文件原始顺序
/// - 反开关都能拿到新的顺序 (每次开关都会重洗)

List<PlayQueueItem> _queue(int count) => [
      for (var i = 0; i < count; i++)
        PlayQueueItem(
          file: FileItem(name: 'v$i', uri: 'v$i', type: ContentType.video),
          index: i,
        ),
    ];

List<int> _indices(List<PlayQueueItem> queue) =>
    queue.map((item) => item.index).toList();

void main() {
  group('getShufflePlayQueue', () {
    test('空队列返回空', () {
      expect(getShufflePlayQueue([], 0), isEmpty);
    });

    test('是一条完整排列, 且当前这条排在最前', () {
      final queue = _queue(8);
      final shuffled = getShufflePlayQueue(queue, 3);

      expect(shuffled.length, queue.length);
      expect(_indices(shuffled).toSet(), _indices(queue).toSet());
      expect(shuffled.first.index, 3);
    });

    test('下标不存在时也不丢条', () {
      final queue = _queue(5);
      final shuffled = getShufflePlayQueue(queue, 99);
      expect(_indices(shuffled).toSet(), _indices(queue).toSet());
    });

    test('单条队列原样返回', () {
      final queue = _queue(1);
      expect(_indices(getShufflePlayQueue(queue, 0)), [0]);
    });
  });

  group('toggleShuffle', () {
    tearDown(() async {
      await useAppStore().updateShuffle(false);
      await usePlayQueueStore().update(playQueue: _queue(0), index: 0);
    });

    test('打开随机: 重新洗牌 (当前这条在最前), 关闭: 恢复原始顺序', () async {
      final queueStore = usePlayQueueStore();
      final appStore = useAppStore();

      await queueStore.update(playQueue: _queue(6), index: 4);
      await appStore.updateShuffle(false);
      // 原始顺序
      expect(_indices(queueStore.state.playQueue), [0, 1, 2, 3, 4, 5]);

      // 打开随机 -> 洗牌 + 标记打开
      await toggleShuffle();
      expect(appStore.state.shuffle, isTrue);
      expect(queueStore.state.playQueue.length, 6);
      expect(_indices(queueStore.state.playQueue).toSet(), {0, 1, 2, 3, 4, 5});
      expect(queueStore.state.playQueue.first.index, 4);
      expect(queueStore.state.currentIndex, 4);

      // 关闭随机 -> 恢复文件原始顺序 + 标记关闭
      await toggleShuffle();
      expect(appStore.state.shuffle, isFalse);
      expect(_indices(queueStore.state.playQueue), [0, 1, 2, 3, 4, 5]);

      // 再次打开 -> 又是一份新的排列 (每次开关都重洗)
      await toggleShuffle(value: true);
      expect(appStore.state.shuffle, isTrue);
      expect(_indices(queueStore.state.playQueue).toSet(), {0, 1, 2, 3, 4, 5});
      expect(queueStore.state.playQueue.first.index, 4);
    });
  });
}
