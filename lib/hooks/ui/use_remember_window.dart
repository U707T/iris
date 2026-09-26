import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

/// 窗口大小/位置/最大化状态记忆。
///
/// 在应用启动时恢复上次保存的窗口状态, 并在窗口被移动/缩放/最大化时
/// 延迟保存, 避免频繁写盘。
void useRememberWindow() {
  final context = useContext();

  final rememberWindowSize =
      useAppStore().select(context, (state) => state.rememberWindowSize);

  final saveTimer = useRef<Timer?>(null);
  final isRestoring = useRef(true);
  final listener = useMemoized(() => _WindowStateListener(), []);

  Future<void> saveWindowState() async {
    if (!isDesktop || !rememberWindowSize) return;
    if (isRestoring.value) return;

    try {
      if (await windowManager.isFullScreen()) return;

      final bool maximized = await windowManager.isMaximized();

      // 最大化时保留上一次的普通窗口尺寸, 仅更新最大化标记
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

  void scheduleSave() {
    if (!isDesktop || !rememberWindowSize) return;
    saveTimer.value?.cancel();
    saveTimer.value =
        Timer(const Duration(milliseconds: 600), saveWindowState);
  }

  Future<bool> isVisibleOnScreen(Rect rect) async {
    try {
      final screens = await window_size.getScreenList();
      if (screens.isEmpty) return true;
      return screens.any((screen) {
        final intersect = screen.visibleFrame.intersect(rect);
        return intersect.width > 100 && intersect.height > 100;
      });
    } catch (_) {
      return true;
    }
  }

  useEffect(() {
    if (!isDesktop) return null;

    Future<void> restore() async {
      final appStore = useAppStore();

      if (!rememberWindowSize) {
        isRestoring.value = false;
        return;
      }

      // 等待持久化状态加载完成
      var waited = 0;
      while (!appStore.isLoaded && waited < 3000) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }

      final bounds = appStore.state.windowBounds;

      try {
        if (bounds != null && bounds.length == 4) {
          final rect =
              Rect.fromLTWH(bounds[0], bounds[1], bounds[2], bounds[3]);
          if (await isVisibleOnScreen(rect)) {
            await windowManager.setBounds(rect);
          }
        }
        if (appStore.state.windowMaximized) {
          await windowManager.maximize();
        }
      } catch (e) {
        logger('Error restoring window state: $e');
      } finally {
        isRestoring.value = false;
      }
    }

    listener.onChange = scheduleSave;
    windowManager.addListener(listener);

    // 等首帧布局完成后再恢复窗口状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), restore);
    });

    return () {
      windowManager.removeListener(listener);
      saveTimer.value?.cancel();
    };
  }, [rememberWindowSize]);
}

class _WindowStateListener extends WindowListener {
  void Function()? onChange;

  @override
  void onWindowResize() => onChange?.call();

  @override
  void onWindowResized() => onChange?.call();

  @override
  void onWindowMove() => onChange?.call();

  @override
  void onWindowMoved() => onChange?.call();

  @override
  void onWindowMaximize() => onChange?.call();

  @override
  void onWindowUnmaximize() => onChange?.call();
}
