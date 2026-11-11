import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/utils/refresh_play_queue.dart';

FileItem _file(String name) => FileItem(
      name: name,
      uri: '/movies/$name',
      path: ['/movies', name],
    );

PlayQueueState _state(List<String> names, int currentIndex) => PlayQueueState(
      playQueue: [
        for (var i = 0; i < names.length; i++)
          PlayQueueItem(file: _file(names[i]), index: i),
      ],
      currentIndex: currentIndex,
    );

/// 「刷新播放列表」的核心规则: 只增删成员, 不重排、不换当前项的实例。
///
/// 最后一条 (实例不换) 是重点: `usePlayerEngine` 的 `useEffect([file])` 认的是
/// FileItem 的相等性, 换了实例就会重新 open —— 刷新一下把正在播的片子从头放,
/// 那是比"刷新无效"更糟的结果。
void main() {
  group('mergeQueueWithListed', () {
    test('保留现有顺序与 index, 新文件追加在末尾', () {
      final state = _state(['a', 'b', 'c'], 1);

      final merged = mergeQueueWithListed(
        state: state,
        listed: [_file('c'), _file('a'), _file('b'), _file('d')],
      );

      expect(merged, isNotNull);
      expect(
        merged!.playQueue.map((e) => e.file.name).toList(),
        ['a', 'b', 'c', 'd'],
      );
      expect(merged.playQueue.map((e) => e.index).toList(), [0, 1, 2, 3]);
      expect(merged.currentIndex, 1);
    });

    test('当前项的 FileItem 实例原样保留 (否则播放器会重新 open)', () {
      final state = _state(['a', 'b'], 0);

      final merged = mergeQueueWithListed(
        state: state,
        listed: [_file('a'), _file('b')],
      );

      expect(merged, isNotNull);
      expect(
        identical(merged!.playQueue.first.file, state.playQueue.first.file),
        isTrue,
      );
    });

    test('目录里消失的文件从队列移除', () {
      final state = _state(['a', 'b', 'c'], 2);

      final merged = mergeQueueWithListed(
        state: state,
        listed: [_file('a'), _file('c')],
      );

      expect(merged!.playQueue.map((e) => e.file.name).toList(), ['a', 'c']);
      // index 是条目的身份, 不因为位置变了就重排
      expect(merged.playQueue.map((e) => e.index).toList(), [0, 2]);
      expect(merged.currentIndex, 2);
    });

    test('当前项被删 -> 落到原位置附近, 不停在已失效的 index 上', () {
      final state = _state(['a', 'b', 'c'], 1);

      final merged = mergeQueueWithListed(
        state: state,
        listed: [_file('a'), _file('c')],
      );

      expect(merged!.currentIndex, 2);
      expect(
        merged.playQueue.any((e) => e.index == merged.currentIndex),
        isTrue,
      );
    });

    test('停止态 (-1) 保持停止, 不凭空指到某一条', () {
      final state = _state(['a', 'b'], -1);

      final merged = mergeQueueWithListed(
        state: state,
        listed: [_file('a')],
      );

      expect(merged!.currentIndex, -1);
    });

    test('一个都对不上 / 队列为空 -> null (不清空正在播的队列)', () {
      expect(
        mergeQueueWithListed(
          state: _state(['a', 'b'], 0),
          listed: [_file('x')],
        ),
        isNull,
      );
      expect(
        mergeQueueWithListed(
          state: _state(const [], 0),
          listed: [_file('a')],
        ),
        isNull,
      );
      expect(
        mergeQueueWithListed(
          state: _state(['a'], 0),
          listed: const [],
        ),
        isNull,
      );
    });
  });

  group('folderOfPlayQueueItem', () {
    test('目录 = path 去掉文件名', () {
      expect(folderOfPlayQueueItem(_file('a.mp4')), ['/movies']);
    });

    test('SAF 目录 (path[0] 是 content:// 目录) 同样只去掉最后一段', () {
      final file = FileItem(
        name: 'a.mp4',
        uri: 'content://dir%2Fa.mp4',
        path: ['content://dir', 'a.mp4'],
      );
      expect(folderOfPlayQueueItem(file), ['content://dir']);
    });

    test('没有目录段 (单个文件 / 在线链接) -> 空, 不回扫整个根', () {
      expect(
        folderOfPlayQueueItem(
          FileItem(name: 'a.mp4', uri: 'https://example.com/a.mp4'),
        ),
        isEmpty,
      );
    });
  });
}
