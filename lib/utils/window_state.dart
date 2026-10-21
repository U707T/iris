import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

/// 立即保存当前窗口位置 / 大小 / 最大化状态。
///
/// 平时由 useRememberWindow 的 600ms 防抖调用；关窗时也要显式 flush 一次，
/// 否则「拖完窗口立刻 Alt+F4」会丢掉最后一次调整。
/// 全屏时不覆盖普通窗口的 bounds，和防抖保存的行为保持一致。
Future<void> saveCurrentWindowState() async {
  if (!isDesktop) return;
  if (!useAppStore().state.rememberWindowSize) return;

  try {
    if (await windowManager.isFullScreen()) return;

    final bool maximized = await windowManager.isMaximized();

    if (maximized) {
      await useAppStore().updateWindowBounds(
        useAppStore().state.windowBounds,
        maximized: true,
      );
      return;
    }

    final bounds = await windowManager.getBounds();
    await useAppStore().updateWindowBounds(
      [bounds.left, bounds.top, bounds.width, bounds.height],
      maximized: false,
    );
  } catch (e) {
    logger('Error saving window state: $e');
  }
}
