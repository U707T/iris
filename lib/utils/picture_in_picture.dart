import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

/// 画中画。
///
/// 两个平台的"画中画"不是同一件东西, 但入口、状态和界面让位规则是一样的:
///
/// - **Android**: 系统 PiP (`Activity.enterPictureInPictureMode`)。原生侧
///   实现见 `MainActivity.kt`, 通道名 [channelName]。用户可按 Home 自动进
///   (API 31+ 用 `setAutoEnterEnabled`, 更老的版本靠 `onUserLeaveHint`),
///   也可以从「更多 → 画中画」手动进; 系统小窗自带关闭 / 展开按钮。
/// - **桌面**: 应用内小窗 —— 保留同一个窗口和同一条解码链路, 只把窗口缩成
///   贴右下角的置顶小窗, 退出时把尺寸 / 位置 / 置顶 / 最大化 / 全屏原样还原。
///   桌面系统没有 PiP 协议, VLC / mpv 也是这么做的。
/// - **iOS**: 未实现 (需要额外插件与原生工程改动), 能力探测固定返回 false,
///   设置项与菜单入口都不会出现。
///
/// 状态是单向的: 平台决定"现在在不在小窗里", 写进
/// [PlayerUiStore.updatePictureInPicture], UI 只读它来决定控制层让不让位。
const String channelName = 'iris/picture_in_picture';
const MethodChannel _channel = MethodChannel(channelName);

/// Android 的 `PictureInPictureParams.setAspectRatio` 只接受 1:2.39 ~ 2.39:1,
/// 超出直接抛 `IllegalArgumentException`。2.4:1 的宽银幕、以及某些把 SAR 算进
/// 宽高比的片子都会越界, 所以进入前统一夹一次 —— 宁可画面两侧多一点黑边,
/// 也好过点了没反应。
const double minPictureInPictureAspect = 0.42;
const double maxPictureInPictureAspect = 2.39;

/// 宽高比未知 (音频 / 还没解出首帧) 时的兜底。
const double fallbackPictureInPictureAspect = 16 / 9;

/// 桌面小窗的默认宽度与贴边留白 (逻辑像素)。
const double pictureInPictureWindowWidth = 420;
const double pictureInPictureWindowMargin = 16;

/// 小窗的宽度下限: 再窄就看不清画面, 也不方便拖拽。
const double pictureInPictureMinimumWidth = 240;

/// 桌面小窗临时放宽的最小窗口尺寸 (普通模式是 [globals.minimumWindowSize])。
const Size pictureInPictureMinimumWindowSize = Size(160, 90);

/// 把任意宽高比收进可用区间; null / 0 / NaN 一律退回 16:9。
///
/// 单独抽出来是因为"夹取规则"同时被 Android 参数、桌面小窗尺寸和测试使用,
/// 三处各写一遍迟早会漂。
double resolvePictureInPictureAspect(double? aspectRatio) {
  if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
    return fallbackPictureInPictureAspect;
  }
  return aspectRatio.clamp(
    minPictureInPictureAspect,
    maxPictureInPictureAspect,
  );
}

/// 现在是否允许系统在"用户离开应用"时自动进画中画。
///
/// 只在**真在放视频**时允许: 暂停时进小窗只会看到一张冻住的画面, 还得手动
/// 关掉; 音频没有画面可看; 短视频模式有自己的播放器池, 画面比例一直在变;
/// 播放失败时更不该把错误提示缩小成 200dp 的小窗。
///
/// 弹层打开时也不允许 —— 播放队列 / 设置 / 对话框都是同一个窗口里的路由,
/// 这时按 Home 进小窗, 用户看到的会是缩小了的设置界面而不是画面。
bool shouldArmAutoPictureInPicture({
  required bool enabled,
  required bool supported,
  required bool isVideo,
  required bool isPlaying,
  required bool isShortVideoMode,
  required bool hasError,
  required bool hasOverlay,
}) {
  return enabled &&
      supported &&
      isVideo &&
      isPlaying &&
      !isShortVideoMode &&
      !hasError &&
      !hasOverlay;
}

/// 桌面小窗的位置与尺寸: 贴工作区右下角, 宽度取 [preferredWidth],
/// 高度按宽高比算; 放不下就先缩高度, 再按比例缩宽度。
///
/// 不直接用"窗口当前尺寸的一半"是因为进入前窗口可能是全屏 / 最大化:
/// 从 3840dp 缩到 1920dp 仍然是一整块屏幕, 那就不叫小窗了。
Rect computePictureInPictureBounds({
  required Rect workArea,
  required double aspectRatio,
  double preferredWidth = pictureInPictureWindowWidth,
  double margin = pictureInPictureWindowMargin,
}) {
  final double aspect = resolvePictureInPictureAspect(aspectRatio);

  final double usableWidth = math.max(1.0, workArea.width - margin * 2);
  final double usableHeight = math.max(1.0, workArea.height - margin * 2);

  double width = math.max(
    math.min(pictureInPictureMinimumWidth, usableWidth),
    math.min(preferredWidth, usableWidth),
  );
  double height = width / aspect;

  // 竖向视频 / 矮屏幕: 高度先顶到工作区, 宽度按比例回收。
  if (height > usableHeight) {
    height = usableHeight;
    width = height * aspect;
  }

  return Rect.fromLTWH(
    math.max(workArea.left + margin, workArea.right - margin - width),
    math.max(workArea.top + margin, workArea.bottom - margin - height),
    width,
    height,
  );
}

/// 画中画入口 / 状态。全部是静态方法: 全局只有一个小窗。
class PictureInPicture {
  PictureInPicture._();

  /// 平台真实状态变化时回调 (Android 系统小窗进入 / 退出, 桌面小窗还原)。
  static void Function(bool isInPictureInPicture)? onModeChanged;

  /// 上一次同步给 Android 的"武装"状态, 避免每次 build 都过一次通道。
  static bool _autoEnter = false;
  static double _autoEnterAspect = fallbackPictureInPictureAspect;

  /// 能力探测结果。main() 启动时写一次, 见 [detectSupport]。
  static bool get isSupported => globals.pictureInPictureSupported;

  /// 启动时探测一次: 桌面恒为 true, Android 问原生, 其余平台 false。
  ///
  /// 顺手把通道回调挂上 —— 只会挂一次, 因为 [detectSupport] 只在 main() 里
  /// 调用; 挂在这里而不是 hook 里, 是为了让"进入小窗"这件事在播放页还没
  /// 建好时也不会丢掉第一帧的状态。
  static Future<bool> detectSupport() async {
    if (!isAndroid) {
      globals.pictureInPictureSupported = isDesktop;
      return globals.pictureInPictureSupported;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPictureInPictureModeChanged') {
        final bool isInPip = call.arguments == true;
        onModeChanged?.call(isInPip);
      }
      return null;
    });

    try {
      final bool supported = await _channel
              .invokeMethod<bool>('isSupported')
              .timeout(const Duration(seconds: 2)) ??
          false;
      globals.pictureInPictureSupported = supported;
    } catch (e) {
      // 老版本没有注册通道 / 系统不给回答: 当作不支持, 设置项直接不出现。
      logger('Picture-in-picture support probe failed: $e');
      globals.pictureInPictureSupported = false;
    }
    return globals.pictureInPictureSupported;
  }

  /// Android: 告诉原生"现在离开应用要不要自动进小窗"。
  ///
  /// 参数变化时才过通道 —— 播放中 isPlaying / aspectRatio 抖动会把这里变成
  /// 一个每帧几十次的方法调用。
  static Future<void> setAutoEnter({
    required bool enabled,
    required double aspectRatio,
  }) async {
    if (!isAndroid || !isSupported) return;

    final double aspect = resolvePictureInPictureAspect(aspectRatio);
    if (_autoEnter == enabled &&
        (_autoEnterAspect - aspect).abs() < 0.001) {
      return;
    }
    _autoEnter = enabled;
    _autoEnterAspect = aspect;

    try {
      await _channel.invokeMethod<void>('setAutoEnter', {
        'enabled': enabled,
        'aspectRatio': aspect,
      });
    } catch (e) {
      logger('Setting auto picture-in-picture failed: $e');
    }
  }

  /// 手动进入。Android 返回系统是否接受; 桌面返回小窗是否开起来。
  static Future<bool> enter({double? aspectRatio}) async {
    if (!isSupported) return false;

    final double aspect = resolvePictureInPictureAspect(aspectRatio);

    if (isDesktop) {
      return _desktopWindow.enter(aspect);
    }

    try {
      final bool entered = await _channel.invokeMethod<bool>('enter', {
            'aspectRatio': aspect,
          }) ??
          false;
      return entered;
    } catch (e) {
      logger('Entering picture-in-picture failed: $e');
      return false;
    }
  }

  /// 退出。
  ///
  /// Android 侧**没有**应用内退出 API —— 系统小窗的关闭 (X) / 展开按钮归系统
  /// 所有, 这里什么都不做 (回到应用 / 关掉小窗由系统回调驱动状态); 桌面小窗
  /// 则把窗口还原。
  static Future<void> exit() async {
    if (isDesktop) {
      await _desktopWindow.exit();
    }
  }
}

/// 桌面小窗: 进入前把窗口状态抄一份, 退出时逐项还原。
///
/// 只动窗口, 不动播放器 —— 解码链路和画中画之前完全一样, 所以不会出现
/// "切小窗要重新缓冲"。
class _DesktopPictureInPictureWindow {
  Rect? _restoreBounds;
  final Size _restoreMinimumSize = globals.minimumWindowSize;
  bool _restoreMaximized = false;
  bool _restoreFullScreen = false;

  Future<bool> enter(double aspectRatio) async {
    if (usePlayerUiStore().state.isPictureInPicture) return true;

    try {
      _restoreFullScreen = await windowManager.isFullScreen();
      _restoreMaximized = await windowManager.isMaximized();
      _restoreBounds = await windowManager.getBounds();

      // 全屏 / 最大化下改尺寸是无效的, 先退出来再量。
      // 全屏走 store 而不是直接调 windowManager: `isFullScreen` 也要跟着变,
      // 否则小窗期间应用仍然"以为自己在全屏", Esc / 标题栏按钮的判断全错。
      if (_restoreFullScreen) {
        await usePlayerUiStore().updateFullScreen(false);
        // 退出全屏还要一帧才能把窗口交回来, 这期间 setBounds 会被忽略
        // (use_resize_window 退出全屏后同样等 50ms)。
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_restoreMaximized) await windowManager.unmaximize();

      final Rect workArea = await _workArea();
      final Rect target = computePictureInPictureBounds(
        workArea: workArea,
        aspectRatio: aspectRatio,
      );

      // 普通模式的最小尺寸是 427x240, 比小窗还大: 不放宽的话 setBounds
      // 会被系统夹回去, 小窗变成"右下角一块 427x240 的普通窗口"。
      await windowManager.setMinimumSize(pictureInPictureMinimumWindowSize);
      await windowManager.setResizable(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBounds(target);
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      // 不调 focus(): 进小窗不该把焦点从用户正在用的窗口抢走, 置顶已经够了。

      usePlayerUiStore().updatePictureInPicture(true);
      return true;
    } catch (e) {
      logger('Entering desktop picture-in-picture failed: $e');
      // 半路失败时别把小窗状态留在 store 里, 否则控制层会一直藏着。
      usePlayerUiStore().updatePictureInPicture(false);
      return false;
    }
  }

  Future<void> exit() async {
    if (!usePlayerUiStore().state.isPictureInPicture) return;

    try {
      await windowManager.setMinimumSize(_restoreMinimumSize);
      // 置顶取 store 里的用户偏好, 而不是进入前抄一份: F10 在小窗里按过之后,
      // 最终状态应该听用户的, 不是回到"进入前"。
      await windowManager.setAlwaysOnTop(
        usePlayerUiStore().state.isAlwaysOnTop,
      );

      final Rect? bounds = _restoreBounds;
      if (bounds != null) await windowManager.setBounds(bounds);
      if (_restoreMaximized) await windowManager.maximize();
      if (_restoreFullScreen) {
        await usePlayerUiStore().updateFullScreen(true);
      }
    } catch (e) {
      logger('Leaving desktop picture-in-picture failed: $e');
    } finally {
      usePlayerUiStore().updatePictureInPicture(false);
      // 回到正常窗口: 控制栏应该立刻在, 而不是等用户再点一下画面。
      usePlayerUiStore().updateIsShowControl(true);
    }
  }

  /// 小窗该贴哪块屏幕: 用窗口当前所在的屏幕, 拿不到就退回主屏。
  Future<Rect> _workArea() async {
    try {
      final window_size.Screen? screen = await window_size.getCurrentScreen();
      if (screen != null) return screen.visibleFrame;

      final List<window_size.Screen> screens =
          await window_size.getScreenList();
      if (screens.isNotEmpty) return screens.first.visibleFrame;
    } catch (e) {
      logger('Reading screen bounds for picture-in-picture failed: $e');
    }
    return const Rect.fromLTWH(0, 0, 1280, 720);
  }
}

final _DesktopPictureInPictureWindow _desktopWindow =
    _DesktopPictureInPictureWindow();
