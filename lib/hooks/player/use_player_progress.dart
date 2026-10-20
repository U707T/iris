import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:media_kit/media_kit.dart';

/// 播放进度：切换文件 / 退出时保存，打开时恢复。
///
/// - 保存用 cleanup 里的**旧闭包**，拿到的就是旧文件的 file（与原实现一致）；
/// - 恢复每个文件只决策一次（duration 会多次变化，重复 seek 会把用户拽回旧进度）；
/// - 换文件时在 build 里同步清掉"已恢复"标记，早于本帧任何 effect。
Future<void> Function() usePlayerProgress({
  required Player player,
  required FileItem? file,
  required Duration duration,
  required bool alwaysPlayFromBeginning,
  required Map<String, Progress> history,
}) {
  final restoredProgressKey = useRef<String?>(null);
  final lastFileId = useRef<String?>(null);

  if (file?.getID() != lastFileId.value) {
    lastFileId.value = file?.getID();
    restoredProgressKey.value = null;
  }

  Future<void> saveProgress() async {
    // Android 的 "open with" content:// 是会话级授权, 不要写进历史
    if (isAndroid &&
        globals.initUri == file?.uri &&
        globals.initUri != null &&
        globals.initUri!.startsWith('content://')) {
      return;
    }

    if (file != null && player.state.duration != Duration.zero) {
      logger(
          'Save progress: ${file.name}, position: ${player.state.position}, duration: ${player.state.duration}');
      useHistoryStore().add(Progress(
        dateTime: DateTime.now().toUtc(),
        position: player.state.position,
        duration: player.state.duration,
        file: file,
      ));
    }
  }

  // 切换文件 / 卸载时保存上一条的进度
  // (cleanup 捕获的是注册时的旧 file, 正好是要保存的那一条)
  useEffect(() {
    return saveProgress;
  }, [file]);

  useEffect(() {
    () async {
      if (duration == Duration.zero) return;
      if (file == null || file.type != ContentType.video) return;

      // history 是异步读盘的: 没读完就下结论 (认为"没有历史") 会把续播
      // 丢掉。读完时 store 的 history 会变化并再次触发本 effect。
      if (!useHistoryStore().isLoaded) return;

      // 每个文件只决策一次: 先占位, 再判断是否恢复 ——
      // 否则播放中保存历史 (打开弹层会 saveProgress) 会让这里再跑一次,
      // 把当前进度当成"旧进度"再 seek 回去。
      if (restoredProgressKey.value == file.getID()) return;
      restoredProgressKey.value = file.getID();

      final progress = history[file.getID()];
      if (progress == null || alwaysPlayFromBeginning) return;

      final remaining = progress.duration.inMilliseconds -
          progress.position.inMilliseconds;
      if (remaining <= 5000) return;

      logger(
          'Resume progress: ${file.name} position: ${progress.position} duration: ${progress.duration}');
      await player.seek(progress.position);
    }();
    return;
    // duration 会多次变化 (探测 / 变分辨率); history 用于等待异步读盘完成。
  }, [duration, history]);

  return saveProgress;
}
