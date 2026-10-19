import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_play_queue_store.dart';

/// 播放队列导航的健壮性:
/// 空队列时按 Ctrl+←/→ / 媒体键不应抛 StateError (此前 `.first` / `.last`
/// 会直接崩在按键回调里)。
List<PlayQueueItem> _queue(int count) => [
      for (var i = 0; i < count; i++)
        PlayQueueItem(
          file: FileItem(name: 'v$i', uri: 'v$i', type: ContentType.video),
          index: i,
        ),
    ];

void main() {
  group('PlayQueueStore 上一条 / 下一条', () {
    test('空队列时不抛异常, 状态保持不变', () async {
      final store = usePlayQueueStore();
      await store.update(playQueue: const [], index: 0);

      await store.previous();
      await store.next();

      expect(store.state.playQueue, isEmpty);
      expect(store.state.currentIndex, 0);
    });

    test('非空队列正常前进 / 后退 / 回绕', () async {
      final store = usePlayQueueStore();
      await store.update(playQueue: _queue(3), index: 0);

      await store.next();
      expect(store.state.currentIndex, 1);

      await store.previous();
      expect(store.state.currentIndex, 0);

      // 第一条再往前 → 回绕到最后一条
      await store.previous();
      expect(store.state.currentIndex, 2);

      // 最后一条再往后 → 回绕到第一条
      await store.next();
      expect(store.state.currentIndex, 0);
    });
  });
}
