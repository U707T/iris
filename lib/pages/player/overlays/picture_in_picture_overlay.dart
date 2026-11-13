import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/overlays/controls_overlay.dart'
    show ControlsOverlay;
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:iris/utils/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

/// 小窗里的最小交互层。
///
/// 正常窗口那一套 (标题栏、控制栏、手势、迷你进度) 在小窗里全都不出现:
/// 240dp 宽的一条控制栏上排十个按钮, 既点不准也看不清。这里只留两件事:
///
/// - **轻点画面 = 播放 / 暂停** (两个平台都有; Android 的系统小窗没有内建
///   播放键, 想暂停只能展开窗口, 这一下正好补上);
/// - **桌面: 拖动移动窗口 + 悬停显示退出按钮**。桌面小窗是无边框窗口, 没有
///   标题栏可拖, 所以整块画面就是拖动区 (普通模式下这个活由手势层干)。
///   Android 的窗口归系统管, 不提供退出按钮 —— 系统小窗自带关闭 / 展开。
class PictureInPictureOverlay extends HookWidget {
  const PictureInPictureOverlay({super.key});

  /// 进入后 / 每次悬停后, 退出按钮停留多久
  static const Duration exitVisibleDuration = Duration(milliseconds: 2200);

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final bool isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);

    final showExit = useState(isDesktop);
    final hideTimer = useRef<Timer?>(null);

    void scheduleHideExit() {
      hideTimer.value?.cancel();
      hideTimer.value = Timer(exitVisibleDuration, () {
        if (context.mounted) showExit.value = false;
      });
    }

    // 刚进小窗时先把退出按钮亮两秒: 否则用户面对一块无边框画面, 不知道
    // 怎么回去 (Esc 是隐藏操作, 不能指望每个人都记得)。
    useEffect(() {
      if (isDesktop) scheduleHideExit();
      return () => hideTimer.value?.cancel();
    }, const []);

    void togglePlayback() {
      final player = context.read<MediaPlayer>();
      if (player.isPlaying) {
        useAppStore().updateAutoPlay(false);
        player.pause();
      } else {
        useAppStore().updateAutoPlay(true);
        player.play();
      }
    }

    return MouseRegion(
      // 悬停时保持常显、离开才开始倒计时。写成 onHover + 每次重启定时器的话,
      // 指针每动一下都会 cancel + 新建一个 Timer。
      onEnter: (_) {
        if (!isDesktop) return;
        hideTimer.value?.cancel();
        showExit.value = true;
      },
      onExit: (_) {
        if (!isDesktop) return;
        scheduleHideExit();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: togglePlayback,
        // 无边框窗口在小窗里没有标题栏, 拖画面就是拖窗口。
        onPanStart: isDesktop ? (_) => windowManager.startDragging() : null,
        child: Stack(
          children: [
            if (isDesktop)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  ignoring: !showExit.value,
                  child: AnimatedOpacity(
                    opacity: showExit.value ? 1 : 0,
                    duration: ControlsOverlay.animationDuration,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: t.exit_picture_in_picture,
                        icon: const Icon(
                          Icons.close_fullscreen_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        onPressed: () => PictureInPicture.exit(),
                      ),
                    ),
                  ),
                ),
              ),
            // 暂停时给一个很轻的提示, 免得小窗里"画面不动"分不清是卡住还是暂停。
            if (!isPlaying)
              Center(
                child: IgnorePointer(
                  child: Icon(
                    Icons.pause_rounded,
                    size: 36,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
