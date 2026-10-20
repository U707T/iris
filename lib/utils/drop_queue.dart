import 'package:iris/models/file.dart';
import 'package:iris/models/store/play_queue_state.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/utils/check_content_type.dart';
import 'package:iris/utils/path_conv.dart';

/// 把拖入的文件路径构造成播放队列。
///
/// 旧实现是"扫第一个文件所在目录, 再按拖入列表过滤": 跨目录拖入时后面的
/// 文件永远匹配不上（被静默丢弃）; 若第一个文件没在目录列表里命中,
/// `currentIndex` 还会指向一个已被过滤掉的条目 —— 结果队列有内容、
/// 但 `file` 解析为 null，什么都不播。
///
/// 这里直接用拖入顺序建队列，index 从 0 重排，currentIndex 固定第一条。
PlayQueueState? buildDropPlayQueue(Iterable<String> paths) {
  final List<FileItem> files = [];
  final Set<String> seen = {};

  for (final path in paths) {
    if (path.isEmpty || !seen.add(path)) continue;

    final type = checkContentType(path);
    if (type != ContentType.video && type != ContentType.audio) continue;

    final segments = pathConv(path);
    files.add(FileItem(
      storageId: localStorageId,
      storageType: StorageType.internal,
      name: segments.isEmpty ? path : segments.last,
      uri: path,
      path: segments,
      type: type,
    ));
  }

  if (files.isEmpty) return null;

  return PlayQueueState(
    playQueue: [
      for (var i = 0; i < files.length; i++)
        PlayQueueItem(file: files[i], index: i),
    ],
    currentIndex: 0,
  );
}
