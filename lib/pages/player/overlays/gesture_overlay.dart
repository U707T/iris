import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/player_gesture_layer.dart';
import 'package:iris/pages/player/gesture/player_levels.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/widgets/speed_boost_effect.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

/// 主窗口的手势 + 指示器层。
///
/// 手势本体全部交给 [PlayerGestureLayer]（与短视频模式同一份实现），
/// 这里只负责把「主窗口专属」的行为接上去（双击中间 = 播放暂停、鼠标拖动窗口、
/// 双指缩放、长按倍速），以及渲染亮度 / 音量 / 缩放 / 倍速指示器。
class GestureOverlay extends HookWidget {
  const GestureOverlay({
    super.key,
    required this.showControl,
    required this.hideControl,
    required this.showProgress,
  });

  final Function() showControl;
  final Function() hideControl;
  final Function() showProgress;

  @override
  Widget build(BuildContext context) {
    final isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);

    final isShowControl =
        usePlayerUiStore().select(context, (state) => state.isShowControl);
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);

    final cursor = useMemoized(
        () => isShowControl || !isPlaying
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        [isShowControl, isPlaying]);

    // 亮度 / 音量：统一走 PlayerLevels（基准值 + 累计位移，不再逐帧累加）
    final levels = useMemoized(() => PlayerLevels(), []);
    useEffect(() {
      return levels.dispose;
    }, [levels]);

    final isLongPress = useState(false);
    final rateBeforeLongPress = useRef<double?>(null);

    void startLongPress() {
      if (!context.read<MediaPlayer>().isPlaying) return;
      rateBeforeLongPress.value = useAppStore().state.rate;
      useAppStore().updateRate(
        useAppStore().state.longPressSpeed,
        persist: false,
      );
      isLongPress.value = true;
    }

    void endLongPress() {
      final restore = rateBeforeLongPress.value;
      if (restore == null) return;
      rateBeforeLongPress.value = null;
      isLongPress.value = false;
      useAppStore().updateRate(restore, persist: false);
    }

    // 组件销毁 / 切模式时必须恢复倍速：onLongPressEnd 不保证一定到达
    useEffect(() {
      return () {
        final restore = rateBeforeLongPress.value;
        if (restore == null) return;
        rateBeforeLongPress.value = null;
        useAppStore().updateRate(restore, persist: false);
      };
    }, const []);

    final isZoomIndicatorVisible = useState(false);
    final zoomHideTimer = useRef<Timer?>(null);
    useEffect(() {
      return () => zoomHideTimer.value?.cancel();
    }, []);

    void showZoomIndicator(bool visible) {
      zoomHideTimer.value?.cancel();
      if (visible) {
        isZoomIndicatorVisible.value = true;
        zoomHideTimer.value = Timer(const Duration(milliseconds: 900), () {
          isZoomIndicatorVisible.value = false;
        });
      } else {
        zoomHideTimer.value = Timer(const Duration(milliseconds: 400), () {
          isZoomIndicatorVisible.value = false;
        });
      }
    }

    return PlayerGestureLayer(
      readPlayer: () => context.read<MediaPlayer>(),
      seekStepSeconds: () => useAppStore().state.seekStepSeconds,
      levels: levels,
      onHover: (event) {
        if (event.kind != PointerDeviceKind.touch) showControl();
      },
      // 桌面端在画面上拖动 = 拖窗口（沿用旧行为，否则无边框窗口没法移动）
      onWindowDrag: isDesktop ? () => windowManager.startDragging() : null,
      onTap: () {
        if (usePlayerUiStore().state.isShowControl) {
          hideControl();
        } else {
          showControl();
        }
      },
      // 双击中间 1/3：桌面端沿用「切全屏」，移动端播放 / 暂停
      onDoubleTapMiddle: () {
        if (isDesktop) {
          usePlayerUiStore().updateFullScreen(
            !usePlayerUiStore().state.isFullScreen,
          );
          return;
        }
        final player = context.read<MediaPlayer>();
        if (player.isPlaying) {
          useAppStore().updateAutoPlay(false);
          player.pause();
          showControl();
        } else {
          useAppStore().updateAutoPlay(true);
          player.play();
        }
      },
      onLongPressStart: startLongPress,
      onLongPressEnd: endLongPress,
      onScrubActiveChanged: (active) {
        // 横滑期间：显示底部进度（迷你进度 / 控制栏进度条都读共享预览值），
        // 并标记「正在 seek」让控制栏自动隐藏避让（否则拖到一半控制栏会消失）。
        usePlayerUiStore().updateIsSeeking(active);
        if (active) showProgress();
      },
      readZoom: () => usePlayerUiStore().state.zoom,
      onZoom: (value) => usePlayerUiStore().updateZoom(value),
      onZoomIndicator: showZoomIndicator,
      child: MouseRegion(
        cursor: cursor,
        child: Stack(
          children: [
            // 长按加速动效 (与短视频模式共用)
            Positioned.fill(
              child: SpeedBoostEffect(visible: isLongPress.value),
            ),

            // 画面缩放指示
            if (isZoomIndicatorVisible.value)
              Positioned.fill(
                child: Center(
                  child: _LevelChip(
                    icon: Icons.zoom_in_rounded,
                    child: Text(
                      '${(zoom * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),

            // 屏幕亮度（左半屏竖滑）
            Positioned.fill(
              child: ValueListenableBuilder<double?>(
                valueListenable: levels.brightness,
                builder: (context, value, _) => value == null
                    ? const SizedBox.shrink()
                    : Center(
                        child: _LevelChip(
                          icon: value == 0
                              ? Icons.brightness_low_rounded
                              : value < 1
                                  ? Icons.brightness_medium_rounded
                                  : Icons.brightness_high_rounded,
                          child: _LevelBar(value: value),
                        ),
                      ),
              ),
            ),

            // 音量（右半屏竖滑）
            Positioned.fill(
              child: ValueListenableBuilder<double?>(
                valueListenable: levels.volume,
                builder: (context, value, _) => value == null
                    ? const SizedBox.shrink()
                    : Center(
                        child: _LevelChip(
                          icon: value == 0
                              ? Icons.volume_mute_rounded
                              : value < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          child: _LevelBar(value: value),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中央指示胶囊（与短视频模式 / 快进提示同一套视觉）
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: LinearProgressIndicator(
        value: value,
        borderRadius: BorderRadius.circular(4),
        backgroundColor: Colors.grey,
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}
