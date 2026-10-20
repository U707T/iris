import 'package:flutter_test/flutter_test.dart';
import 'package:iris/utils/drop_queue.dart';

/// 拖放建队列:
/// - 跨目录拖入不丢文件（旧实现只扫第一个文件所在目录）
/// - index 从 0 重排, currentIndex 固定第一条（否则可能指向被过滤的条目 → 什么都不播）
/// - 非媒体 / 重复路径被过滤
void main() {
  test('跨目录拖入: 全部保留, 按拖入顺序重排 index', () {
    final queue = buildDropPlayQueue([
      r'C:\a\one.mp4',
      r'D:\b\two.mkv',
      '/mnt/c/three.mp3',
    ]);

    expect(queue, isNotNull);
    expect(queue!.currentIndex, 0);
    expect(queue.playQueue.map((e) => e.index).toList(), [0, 1, 2]);
    expect(queue.playQueue.map((e) => e.file.name).toList(),
        ['one.mp4', 'two.mkv', 'three.mp3']);
    expect(queue.playQueue.first.file.uri, r'C:\a\one.mp4');
  });

  test('非媒体文件与重复路径被过滤', () {
    final queue = buildDropPlayQueue([
      '/videos/a.mp4',
      '/videos/readme.txt',
      '/videos/a.mp4',
      '/videos/b.mp3',
      '',
    ]);

    expect(queue!.playQueue, hasLength(2));
    expect(queue.playQueue.map((e) => e.file.name).toList(), ['a.mp4', 'b.mp3']);
  });

  test('没有可播放文件时返回 null', () {
    expect(buildDropPlayQueue(['/x/a.txt', '/x/b.jpg']), isNull);
    expect(buildDropPlayQueue(const []), isNull);
  });
}
