import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/refresh_play_queue.dart';

/// 「刷新播放列表」的端到端路径: 真的去扫一个临时目录。
///
/// 纯合并规则见 `refresh_play_queue_test.dart`; 这里验的是合并**之前**那一段 ——
/// 从队列条目反推目录、按 storageId / path 找回存储、媒体过滤、排序。这一段的
/// 错误在纯函数测试里看不见 (路径拼错 → 扫到空目录 → 队列被清空)。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('iris_refresh');
    for (final name in ['a.mp4', 'b.mp4', 'c.mkv', 'notes.txt']) {
      await File('${dir.path}/$name').writeAsBytes(const <int>[0]);
    }
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  FileItem item(String name) => FileItem(
        name: name,
        uri: '${dir.path}/$name',
        path: [dir.path, name],
        type: ContentType.video,
      );

  Future<void> ready() => usePlayQueueStore().ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

  test('回扫目录: 新增的追加到末尾, 非媒体文件不进队列', () async {
    await ready();
    final store = usePlayQueueStore();
    final a = item('a.mp4');
    final b = item('b.mp4');
    store.set(PlayQueueState(
      playQueue: [
        PlayQueueItem(file: a, index: 0),
        PlayQueueItem(file: b, index: 1),
      ],
      currentIndex: 1,
    ));

    final int? count =
        await refreshPlayQueue().timeout(const Duration(seconds: 20));

    // a.mp4 / b.mp4 / c.mkv; notes.txt 不是媒体
    expect(count, 3);
    expect(
      store.state.playQueue.map((e) => e.file.name).toList(),
      ['a.mp4', 'b.mp4', 'c.mkv'],
    );
    // 当前项的实例没换 → 播放器不会重新 open
    expect(identical(store.state.playQueue[1].file, b), isTrue);
    expect(store.state.currentIndex, 1);
  });

  test('目录没变时不算"改过": 不写状态 (不落盘, 也不触发重建)', () async {
    await ready();
    final store = usePlayQueueStore();
    store.set(PlayQueueState(
      playQueue: [
        PlayQueueItem(file: item('a.mp4'), index: 0),
        PlayQueueItem(file: item('b.mp4'), index: 1),
        PlayQueueItem(file: item('c.mkv'), index: 2),
      ],
      currentIndex: 0,
    ));

    // 一次 set 就是一次重建 + 一次落盘; 目录没变就不该有
    var writes = 0;
    final subscription = store.stream.listen((_) => writes++);
    addTearDown(subscription.cancel);

    final int? count =
        await refreshPlayQueue().timeout(const Duration(seconds: 20));

    expect(count, 3);
    expect(writes, 0, reason: '目录没变却写了状态');
  });

  test('目录里删掉文件后刷新: 该条移除, 当前项落到原位置附近', () async {
    await ready();
    final store = usePlayQueueStore();
    final b = item('b.mp4');
    store.set(PlayQueueState(
      playQueue: [
        PlayQueueItem(file: item('a.mp4'), index: 0),
        PlayQueueItem(file: b, index: 1),
      ],
      currentIndex: 1,
    ));

    await File('${dir.path}/b.mp4').delete();
    final int? count =
        await refreshPlayQueue().timeout(const Duration(seconds: 20));

    expect(count, 2);
    expect(
      store.state.playQueue.map((e) => e.file.name).toList(),
      ['a.mp4', 'c.mkv'],
    );
    // b 没了: 当前项退到原位置 (下标 1) 那条, 而不是停在已失效的 index 上
    final current = store.state.playQueue
        .firstWhere((e) => e.index == store.state.currentIndex);
    expect(current.file.name, 'c.mkv');
  });
}
