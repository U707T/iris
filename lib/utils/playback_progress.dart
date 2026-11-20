import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';

/// 播放进度标签：`42%` / `100%`，没有可显示的进度时返回 null。
///
/// 文件列表、播放队列、历史三处以前各写一遍这段计算，而且都没防
/// `duration == 0` —— 一个还没探出时长的条目会显示 `NaN%`。这里只写一次。
String? playbackProgressLabel(Progress? progress) {
  if (progress == null || progress.file.type != ContentType.video) return null;
  if (progress.duration.inMilliseconds <= 0) return null;

  final remaining =
      progress.duration.inMilliseconds - progress.position.inMilliseconds;
  if (remaining <= 5000) return '100%';

  final percent =
      progress.position.inMilliseconds / progress.duration.inMilliseconds * 100;
  return '${percent.toStringAsFixed(0)}%';
}
