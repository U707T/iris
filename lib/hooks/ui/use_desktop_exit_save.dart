import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/pages/player/player_handoff.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端关窗: 先保存播放进度, 再真正销毁窗口。
///
/// Windows / Linux / macOS 的 Alt+F4、任务栏关闭、系统关机不会经过
/// `AppLifecycleState.paused`（那是移动端的信号），所以
/// `useAppLifecycle` 里的保存不会触发。这里拦截 WM_CLOSE:
/// `setPreventClose(true)` 之下窗口不会自己关闭, 必须由监听器调用
/// `destroy()`，否则窗口关不掉。
///
/// 监听器挂在 Home 上（不随普通/短视频模式切换卸载），播放器取
/// [activeHandoffPlayer]（当前宿主注册的实例），两种模式都能保存。
void useDesktopExitSave() {
  useEffect(() {
    if (!isDesktop) return null;

    final listener = _WindowCloseListener(() async {
      try {
        await activeHandoffPlayer?.saveProgress();
      } catch (e) {
        logger('Save progress before exit failed: $e');
      } finally {
        // 无论保存成功与否都必须销毁, 否则 setPreventClose 会把窗口卡住
        await windowManager.destroy();
      }
    });

    // macOS / Linux / Windows 都实现了 preventClose; 万一平台调用失败,
    // 退回"正常关窗"也比留下一个关不掉的窗口好。
    unawaited(windowManager.setPreventClose(true).catchError((Object e) {
      logger('setPreventClose failed: $e');
    }));
    windowManager.addListener(listener);

    return () {
      windowManager.removeListener(listener);
    };
  }, const []);
}

class _WindowCloseListener extends WindowListener {
  _WindowCloseListener(this.onClose);

  final Future<void> Function() onClose;

  /// WM_CLOSE 可能重复到达 (用户连点), 只处理第一次
  bool _handled = false;

  @override
  void onWindowClose() {
    if (_handled) return;
    _handled = true;
    unawaited(onClose());
  }
}
