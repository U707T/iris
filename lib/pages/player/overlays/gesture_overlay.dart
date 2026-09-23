import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/use_gesture.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:provider/provider.dart';

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
    final rate = useAppStore().select(context, (state) => state.rate);

    final cursor = useMemoized(
        () => isShowControl || !isPlaying
            ? SystemMouseCursors.basic
            : SystemMouseCursors.none,
        [isShowControl, isPlaying]);

    final gesture = useGesture(
      showControl: showControl,
      hideControl: hideControl,
      showProgress: showProgress,
    );

    return MouseRegion(
      cursor: cursor,
      onHover: gesture.onHover,
      child: Listener(
        onPointerDown: gesture.onPointerDown,
        onPointerMove: gesture.onPointerMove,
        onPointerUp: gesture.onPointerUp,
        onPointerCancel: gesture.onPointerCancel,
        onPointerSignal: gesture.onPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: gesture.onTap,
          onTapDown: gesture.onTapDown,
          onDoubleTapDown: gesture.onDoubleTapDown,
          onLongPressStart: gesture.onLongPressStart,
          onLongPressMoveUpdate: gesture.onLongPressMoveUpdate,
          onLongPressEnd: gesture.onLongPressEnd,
          onLongPressCancel: gesture.onLongPressCancel,
          onPanStart: gesture.onPanStart,
          onPanUpdate: gesture.onPanUpdate,
          onPanEnd: gesture.onPanEnd,
          onPanCancel: gesture.onPanCancel,
          child: Stack(
            children: [
              // 长按加速指示
              if (gesture.isLongPress)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${rate}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 画面缩放指示
              if (gesture.isZoomIndicatorVisible)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(zoom * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 屏幕亮度
              if (gesture.isLeftGesture && gesture.brightness != null)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            gesture.brightness == 0
                                ? Icons.brightness_low_rounded
                                : gesture.brightness! < 1
                                    ? Icons.brightness_medium_rounded
                                    : Icons.brightness_high_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              value: gesture.brightness,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: Colors.grey,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 音量
              if (gesture.isRightGesture && gesture.volume != null)
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            gesture.volume == 0
                                ? Icons.volume_mute_rounded
                                : gesture.volume! < 0.5
                                    ? Icons.volume_down_rounded
                                    : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              value: gesture.volume,
                              borderRadius: BorderRadius.circular(4),
                              backgroundColor: Colors.grey,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
