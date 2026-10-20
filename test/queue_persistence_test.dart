import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/utils/queue_persistence.dart';

/// 播放队列落盘策略:
/// - 普通队列原样存;
/// - 混合队列只剔除 content:// (SAF) 条目, 其余照存 (旧实现整份不存);
/// - currentIndex 必须映射到存活条目, 不能指向被剔除的那条;
/// - 全是 SAF 时保留上一次快照, 不要把用户原来的队列擦成空。
PlayQueueItem _item(int index, String uri) => PlayQueueItem(
      file: FileItem(name: 'f$index', uri: uri, type: ContentType.video),
      index: index,
    );

PlayQueueState _state(List<PlayQueueItem> items, int currentIndex) =>
    PlayQueueState(playQueue: items, currentIndex: currentIndex);

void main() {
  group('persistedQueueState', () {
    test('没有 content:// 条目: 原样返回', () {
      final state = _state([
        _item(0, '/v/a.mp4'),
        _item(1, 'https://example.com/b.mp4'),
        _item(2, 'webdav://c.mp4'),
      ], 1);

      expect(identical(persistedQueueState(state), state), isTrue);
    });

    test('空队列: 照常保存 (用户确实清空了)', () {
      final state = _state(const [], 0);
      expect(identical(persistedQueueState(state), state), isTrue);
    });

    test('混合队列: 剔除 content:// 条目, 索引映射到下一条可恢复项', () {
      final state = _state([
        _item(0, '/v/a.mp4'),
        _item(1, 'content://media/1'),
        _item(2, '/v/c.mp4'),
      ], 1);

      final snapshot = persistedQueueState(state)!;

      expect(snapshot.playQueue.map((e) => e.index).toList(), [0, 2]);
      expect(snapshot.currentIndex, 2, reason: '当前条是 SAF, 应落到下一条');
    });

    test('混合队列: 当前条是最后一条 SAF 时落到最后一条可恢复项', () {
      final state = _state([
        _item(0, '/v/a.mp4'),
        _item(1, '/v/b.mp4'),
        _item(2, 'content://media/2'),
      ], 2);

      final snapshot = persistedQueueState(state)!;

      expect(snapshot.playQueue.map((e) => e.index).toList(), [0, 1]);
      expect(snapshot.currentIndex, 1);
    });

    test('混合队列: 当前条本身可恢复时索引不变', () {
      final state = _state([
        _item(0, '/v/a.mp4'),
        _item(1, 'content://media/1'),
        _item(2, '/v/c.mp4'),
      ], 2);

      final snapshot = persistedQueueState(state)!;

      expect(snapshot.playQueue.map((e) => e.index).toList(), [0, 2]);
      expect(snapshot.currentIndex, 2);
    });

    test('全是 SAF: 默认返回 null (保留上一次快照, 不写空队列)', () {
      final state = _state([
        _item(0, 'content://media/0'),
        _item(1, 'content://media/1'),
      ], 0);

      expect(persistedQueueState(state), isNull);
    });

    test('全是 SAF 且来自删除路径: 写空队列, 不让已删条目复活', () {
      final state = _state([
        _item(0, 'content://media/0'),
      ], 0);

      final snapshot = persistedQueueState(
        state,
        keepPreviousWhenEmpty: false,
      )!;

      expect(snapshot.playQueue, isEmpty);
      expect(snapshot.currentIndex, 0);
    });

    test('停止态 (-1) 不会被改写成某一条', () {
      final state = _state([
        _item(0, '/v/a.mp4'),
        _item(1, 'content://media/1'),
      ], -1);

      final snapshot = persistedQueueState(state)!;

      expect(snapshot.playQueue.map((e) => e.index).toList(), [0]);
      expect(snapshot.currentIndex, -1);
    });
  });
}
