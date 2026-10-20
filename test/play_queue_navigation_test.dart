import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/queue_navigation.dart';

/// 播放队列导航的健壮性:
/// - 空队列时按上一条 / 下一条 (Ctrl+←/→、媒体键) 不应抛 StateError
///   (此前 `.first` / `.last` 会直接崩在按键回调里);
/// - 一条播完后的自动连播不能越界 (删掉最后一条后播完会取 `playQueue[0]`)。

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

  group('播完之后的下一条', () {
    test('空队列: 返回 null (不再越界)', () {
      expect(
        nextIndexOnCompleted(
          playQueue: const [],
          currentPlayIndex: 0,
          repeat: Repeat.all,
        ),
        isNull,
      );
    });

    test('当前项已不在队列里 (停止 / 已删除): 返回 null', () {
      expect(
        nextIndexOnCompleted(
          playQueue: _queue(3),
          currentPlayIndex: -1,
          repeat: Repeat.all,
        ),
        isNull,
      );
    });

    test('中间项: 前进一条', () {
      expect(
        nextIndexOnCompleted(
          playQueue: _queue(3),
          currentPlayIndex: 1,
          repeat: Repeat.none,
        ),
        2,
      );
    });

    test('最后一条 + 列表循环: 回到第一条', () {
      expect(
        nextIndexOnCompleted(
          playQueue: _queue(3),
          currentPlayIndex: 2,
          repeat: Repeat.all,
        ),
        0,
      );
    });

    test('最后一条 + 不循环: 原地不动', () {
      expect(
        nextIndexOnCompleted(
          playQueue: _queue(3),
          currentPlayIndex: 2,
          repeat: Repeat.none,
        ),
        isNull,
      );
    });

    test('单条循环: 原地不动', () {
      expect(
        nextIndexOnCompleted(
          playQueue: _queue(3),
          currentPlayIndex: 0,
          repeat: Repeat.one,
        ),
        isNull,
      );
    });
  });
}
