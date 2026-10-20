import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/storages/local.dart';

/// 从命令行 / 关联打开时可能是相对路径（`iris movie.mp4`）。
/// 旧实现直接拿相对路径去 split，dirPath 为空 -> Directory('') 不存在
/// -> 队列为空 -> 什么都不播。这里锁住"相对路径也能正确定位并选中"。
void main() {
  late Directory tempDir;
  late Directory originalCwd;

  setUp(() async {
    originalCwd = Directory.current;
    tempDir = await Directory.systemTemp.createTemp('iris_queue_test');
    await File('${tempDir.path}/a.mp4').create();
    await File('${tempDir.path}/b.mkv').create();
    await File('${tempDir.path}/c.mp3').create();
    await File('${tempDir.path}/note.txt').create();
    Directory.current = tempDir;
  });

  tearDown(() async {
    Directory.current = originalCwd;
    await tempDir.delete(recursive: true);
  });

  test('相对路径: 在当前目录建队列并选中该文件', () async {
    final queue = await getLocalPlayQueue('b.mkv');

    expect(queue, isNotNull);
    expect(queue!.playQueue, hasLength(3));
    expect(queue.currentIndex, 1);
    expect(queue.playQueue[queue.currentIndex].file.name, 'b.mkv');
  });

  test('绝对路径: 同样能选中', () async {
    final queue = await getLocalPlayQueue('${tempDir.path}/c.mp3');

    expect(queue, isNotNull);
    expect(queue!.currentIndex, 2);
    expect(queue.playQueue[queue.currentIndex].file.name, 'c.mp3');
  });

  test('非媒体文件返回 null', () async {
    expect(await getLocalPlayQueue('note.txt'), isNull);
  });
}
