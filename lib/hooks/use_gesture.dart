import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:iris/hooks/use_brightness.dart';
import 'package:iris/hooks/use_volume.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class Gesture {
  final void Function(TapDownDetails) onTapDown;
  final void Function() onTap;
  final void Function(TapDownDetails) onDoubleTapDown;
  final void Function(LongPressStartDetails) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;
  final void Function() onLongPressCancel;
  final void Function(DragStartDetails) onPanStart;
  final void Function(DragUpdateDetails) onPanUpdate;
  final void Function(DragEndDetails) onPanEnd;
  final void Function() onPanCancel;
  final void Function(PointerHoverEvent) onHover;
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerMoveEvent) onPointerMove;
  final void Function(PointerUpEvent) onPointerUp;
  final void Function(PointerCancelEvent) onPointerCancel;
  final void Function(PointerSignalEvent) onPointerSignal;

  final bool isLongPress;
  final bool isLeftGesture;
  final bool isRightGesture;
  final bool isZoomIndicatorVisible;
  final double? brightness;
  final double? volume;
  final double zoom;

  Gesture({
    required this.onTapDown,
    required this.onTap,
    required this.onDoubleTapDown,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onHover,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onPointerSignal,
    required this.isLongPress,
    required this.isLeftGesture,
    required this.isRightGesture,
    required this.isZoomIndicatorVisible,
    required this.brightness,
    required this.volume,
    required this.zoom,
  });
}

Gesture useGesture({
  required void Function() showControl,
  required void Function() hideControl,
  required void Function() showProgress,
}) {
  final context = useContext();

  final gestureState = useRef({
    'isTouch': false,
    'isLongPress': false,
    'isDragging': false,
    'startPanOffset': Offset.zero,
    'startSeekPosition': Duration.zero,
    'panDirection': null, // null: 未确定, Axis.horizontal, Axis.vertical
    'rateBeforeLongPress': null,
  });

  final isLeftGesture = useState(false);
  final isRightGesture = useState(false);
  final isLongPressState = useState(false);

  final brightness = useBrightness(isLeftGesture.value);
  final volume = useVolume(isRightGesture.value);

  // 缩放 (Pinch to zoom)
  final activePointers = useRef<Map<int, Offset>>({});
  final pinchStartDistance = useRef<double?>(null);
  final pinchStartZoom = useRef<double>(1.0);
  final isPinching = useRef<bool>(false);

  final isZoomIndicatorVisible = useState(false);
  final zoomHideTimer = useRef<Timer?>(null);

  useEffect(() {
    return () {
      zoomHideTimer.value?.cancel();
    };
  }, []);

  void showZoomIndicator() {
    isZoomIndicatorVisible.value = true;
    zoomHideTimer.value?.cancel();
    zoomHideTimer.value = Timer(const Duration(milliseconds: 900), () {
      isZoomIndicatorVisible.value = false;
    });
  }

  void hideZoomIndicator() {
    zoomHideTimer.value?.cancel();
    zoomHideTimer.value = Timer(const Duration(milliseconds: 400), () {
      isZoomIndicatorVisible.value = false;
    });
  }

  void onTapDown(TapDownDetails details) {
    if (details.kind == PointerDeviceKind.touch) {
      gestureState.value['isTouch'] = true;
    }
  }

  void onTap() {
    if (usePlayerUiStore().state.isShowControl) {
      hideControl();
    } else {
      showControl();
    }
  }

  void onDoubleTapDown(TapDownDetails details) {
    final player = context.read<MediaPlayer>();

    if (details.kind == PointerDeviceKind.touch) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final tapDx = details.globalPosition.dx;

      if (tapDx > screenWidth * 0.75) {
        // 右侧 25%
        showProgress();
        player.forward(10);
      } else if (tapDx < screenWidth * 0.25) {
        // 左侧 25%
        showProgress();
        player.backward(10);
      } else {
        // 中间 50%
        if (player.isPlaying) {
          useAppStore().updateAutoPlay(false);
          player.pause();
          showControl();
        } else {
          useAppStore().updateAutoPlay(true);
          player.play();
        }
      }
    } else if (isDesktop) {
      // 桌面端双击切换全屏
      usePlayerUiStore()
          .updateFullScreen(!usePlayerUiStore().state.isFullScreen);
    }
  }

  /// 长按加速: 按住时切换到设置中指定的倍速, 松开后恢复原速
  void onLongPressStart(LongPressStartDetails details) {
    if (!(gestureState.value['isTouch'] as bool)) return;
    if (!context.read<MediaPlayer>().isPlaying) return;

    gestureState.value['isLongPress'] = true;
    isLongPressState.value = true;
    gestureState.value['startPanOffset'] = details.globalPosition;
    gestureState.value['rateBeforeLongPress'] = useAppStore().state.rate;

    final longPressSpeed = useAppStore().state.longPressSpeed;
    logger('Long press speed: $longPressSpeed');
    useAppStore().updateRate(longPressSpeed, persist: false);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    // 长按期间不支持拖动调节, 松开后恢复原速
    return;
  }

  void restoreRateAfterLongPress() {
    if (!(gestureState.value['isLongPress'] as bool)) return;
    final restoreRate =
        gestureState.value['rateBeforeLongPress'] as double? ?? 1.0;
    useAppStore().updateRate(restoreRate, persist: false);
    gestureState.value['rateBeforeLongPress'] = null;
  }

  void onLongPressEnd(LongPressEndDetails details) {
    restoreRateAfterLongPress();
    gestureState.value['isLongPress'] = false;
    isLongPressState.value = false;
    gestureState.value['isTouch'] = false;
  }

  void onLongPressCancel() {
    restoreRateAfterLongPress();
    gestureState.value['isLongPress'] = false;
    isLongPressState.value = false;
    gestureState.value['isTouch'] = false;
  }

  void onPanStart(DragStartDetails details) {
    if (isDesktop && details.kind != PointerDeviceKind.touch) {
      windowManager.startDragging();
      return;
    }

    if (isPinching.value) return;

    if (gestureState.value['isLongPress'] as bool) {
      return;
    }

    if (details.kind == PointerDeviceKind.touch) {
      const double edgeDeadZone = 48.0;
      final screenSize = MediaQuery.sizeOf(context);
      final startDx = details.globalPosition.dx;

      if (startDx < edgeDeadZone || startDx > screenSize.width - edgeDeadZone) {
        logger("Edge swipe detected. Ignoring for system navigation.");
        return;
      }

      gestureState.value['isTouch'] = true;
      gestureState.value['isDragging'] = true;
      gestureState.value['startPanOffset'] = details.globalPosition;
      gestureState.value['startSeekPosition'] =
          context.read<MediaPlayer>().position;
      gestureState.value['panDirection'] = null;
      isLeftGesture.value = false;
      isRightGesture.value = false;
    }
  }

  void onPanUpdate(DragUpdateDetails details) {
    if (isPinching.value) return;
    if (!(gestureState.value['isDragging'] as bool)) return;

    final startOffset = gestureState.value['startPanOffset'] as Offset;
    final totalDx = details.globalPosition.dx - startOffset.dx;
    final totalDy = details.globalPosition.dy - startOffset.dy;

    // 增加手势“死区”，防止误触
    const double panDeadzone = 8.0;
    if (gestureState.value['panDirection'] == null) {
      if (totalDx.abs() > panDeadzone || totalDy.abs() > panDeadzone) {
        gestureState.value['panDirection'] =
            totalDx.abs() > totalDy.abs() ? Axis.horizontal : Axis.vertical;
      }
    }

    final direction = gestureState.value['panDirection'];
    if (direction == null) return;

    // 水平滑动 (Seek)
    if (direction == Axis.horizontal) {
      if (!usePlayerUiStore().state.isSeeking) {
        usePlayerUiStore().updateIsSeeking(true);
      }

      const double sensitivity = 3.0; // 每滑动3像素代表1秒
      final double seekSecondsOffset = totalDx / sensitivity;
      final startSeconds =
          (gestureState.value['startSeekPosition'] as Duration).inSeconds;

      int targetSeconds = (startSeconds + seekSecondsOffset).round();

      // 边界检查
      targetSeconds = targetSeconds.clamp(
          0, context.read<MediaPlayer>().duration.inSeconds);

      context.read<MediaPlayer>().seek(Duration(seconds: targetSeconds));
      showProgress();
    }

    // 垂直滑动 (亮度和音量)
    if (direction == Axis.vertical) {
      // 仅在垂直滑动开始时判断一次左右区域
      if (!isLeftGesture.value && !isRightGesture.value) {
        isLeftGesture.value =
            startOffset.dx < MediaQuery.sizeOf(context).width / 2;
        isRightGesture.value = !isLeftGesture.value;

        if (isRightGesture.value) {
          FlutterVolumeController.updateShowSystemUI(false);
        }
      }

      final double dy = details.delta.dy;

      if (isLeftGesture.value && brightness.value != null) {
        final newBrightness = brightness.value! - dy / 200;
        brightness.value = newBrightness.clamp(0.0, 1.0);
      }

      if (isRightGesture.value && volume.value != null) {
        final newVolume = volume.value! - dy / 200;
        volume.value = newVolume.clamp(0.0, 1.0);
      }
    }
  }

  // ignore: no_leading_underscores_for_local_identifiers
  void _resetPanState() {
    if (usePlayerUiStore().state.isSeeking) {
      usePlayerUiStore().updateIsSeeking(false);
    }
    gestureState.value = {
      ...gestureState.value,
      'isDragging': false,
      'panDirection': null,
    };
    isLeftGesture.value = false;
    isRightGesture.value = false;

    FlutterVolumeController.updateShowSystemUI(true);
  }

  void onPanEnd(DragEndDetails details) => _resetPanState();
  void onPanCancel() => _resetPanState();

  void onHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.touch) {
      usePlayerUiStore().updateIsHovering(true);
      showControl();
    }
  }

  /// 双指捏合缩放画面
  void onPointerDown(PointerDownEvent event) {
    activePointers.value[event.pointer] = event.position;

    if (activePointers.value.length == 2) {
      final points = activePointers.value.values.toList();
      pinchStartDistance.value = (points[0] - points[1]).distance;
      pinchStartZoom.value = usePlayerUiStore().state.zoom;
      isPinching.value = true;

      // 取消可能已经开始的其他手势, 避免冲突
      gestureState.value['isDragging'] = false;
      gestureState.value['panDirection'] = null;
      if (usePlayerUiStore().state.isSeeking) {
        usePlayerUiStore().updateIsSeeking(false);
      }
      isLeftGesture.value = false;
      isRightGesture.value = false;
      FlutterVolumeController.updateShowSystemUI(true);

      showZoomIndicator();
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (!activePointers.value.containsKey(event.pointer)) return;
    activePointers.value[event.pointer] = event.position;

    if (!isPinching.value || activePointers.value.length < 2) return;

    final points = activePointers.value.values.toList();
    final distance = (points[0] - points[1]).distance;
    final startDistance = pinchStartDistance.value;

    if (startDistance == null || startDistance <= 0) return;

    final scale = distance / startDistance;
    usePlayerUiStore().updateZoom(pinchStartZoom.value * scale);
    showZoomIndicator();
  }

  void onPointerUp(PointerUpEvent event) {
    activePointers.value.remove(event.pointer);
    if (activePointers.value.length < 2) {
      isPinching.value = false;
      pinchStartDistance.value = null;
      hideZoomIndicator();
    }
  }

  void onPointerCancel(PointerCancelEvent event) {
    activePointers.value.remove(event.pointer);
    if (activePointers.value.length < 2) {
      isPinching.value = false;
      pinchStartDistance.value = null;
      hideZoomIndicator();
    }
  }

  /// 桌面端 Ctrl + 滚轮无级缩放画面
  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      final delta = -event.scrollDelta.dy / 500.0;
      if (delta == 0) return;
      usePlayerUiStore().updateZoom(usePlayerUiStore().state.zoom + delta);
      showZoomIndicator();
    }
  }

  return Gesture(
    onTapDown: onTapDown,
    onTap: onTap,
    onDoubleTapDown: onDoubleTapDown,
    onLongPressStart: onLongPressStart,
    onLongPressMoveUpdate: onLongPressMoveUpdate,
    onLongPressEnd: onLongPressEnd,
    onLongPressCancel: onLongPressCancel,
    onPanStart: onPanStart,
    onPanUpdate: onPanUpdate,
    onPanEnd: onPanEnd,
    onPanCancel: onPanCancel,
    onHover: onHover,
    onPointerDown: onPointerDown,
    onPointerMove: onPointerMove,
    onPointerUp: onPointerUp,
    onPointerCancel: onPointerCancel,
    onPointerSignal: onPointerSignal,
    isLongPress: isLongPressState.value,
    isLeftGesture: isLeftGesture.value,
    isRightGesture: isRightGesture.value,
    isZoomIndicatorVisible: isZoomIndicatorVisible.value,
    brightness: brightness.value,
    volume: volume.value,
    zoom: usePlayerUiStore().state.zoom,
  );
}
