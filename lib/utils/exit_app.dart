import 'package:flutter/services.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// 统一退出入口。
///
/// - 先保存当前播放进度；
/// - 桌面走正常的 WM_CLOSE（交给 useDesktopExitSave 收尾）；
/// - 移动端只调用 SystemNavigator.pop()，不要再跟 exit(0)。
///   exit(0) 会在 Activity 结束时直接杀掉 Dart 进程，队列 / 设置 / 历史
///   里尚未完成的异步写入没有机会落地。
Future<void> exitApp(MediaPlayer? player) async {
  try {
    await player?.saveProgress();
  } catch (e) {
    logger('Save progress before exit failed: $e');
  }

  if (isDesktop) {
    await windowManager.close();
  } else {
    await SystemNavigator.pop();
  }
}
