import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/player_drag_recognizer.dart';
import 'package:iris/pages/player/gesture/player_levels.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';

/// 播放器的统一手势层（主窗口 / 短视频模式共用同一份实现）。
///
/// 为什么必须共用：此前两边是两套代码，参数和语义都不一样，用户感受到的就是
/// 「同一个动作，两个模式反应不同」——
///
/// | | 主窗口（旧） | 短视频（旧） |
/// |---|---|---|
/// | 进入阈值 | 8px 死区 + `abs(dx)>abs(dy)` | 系统 touchSlop ≈18px，斜滑直接进 |
/// | 拖动时 | **不暂停**，边播边跳 | 暂停 |
/// | 进度反馈 | 底部细线（控件隐藏后只剩它） | 底部时间 + 气泡 |
/// | 松手 | 补发 seek | 补发 seek + 续播 |
/// | 双击分区 | 左/右 25% | 左/右 25% |
/// | 双击提示 | 无 | 中央 `+5s` |
///
/// 现在统一为（口径参考 panelFM 的播放器手势）：
/// 1. 8dp 死区 + 1.4 倍主轴优势比，方向不明确时保持未定 —— 斜滑不再乱跳；
/// 2. 横滑 = 进度：按下即暂停、本地预览实时跟手、120ms 节流 seek、松手精确落点并续播；
/// 3. 竖滑 = 左亮度 / 右音量（主窗口），短视频交给 PageView 翻页；
/// 4. 双击左/右 1/3 = 快退 / 快进（步长取设置），中间 1/3 = 播放暂停，两侧都给出 `±Ns` 提示；
/// 5. 长按 = 倍速，松手恢复；屏幕左右 48px 留给系统返回手势。
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({
    super.key,
    required this.child,
    required this.readPlayer,
    required this.seekStepSeconds,
    required this.onTap,
    required this.onDoubleTapMiddle,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    this.levels,
    this.allowVertical = true,
    this.onScrubActiveChanged,
    this.onHover,
    this.onWindowDrag,
    this.readZoom,
    this.onZoom,
    this.onZoomIndicator,
  });

  final Widget child;

  /// 取当前实时播放器实例（不能缓存：快照里的 position / isPlaying 会过期）
  final MediaPlayer Function() readPlayer;

  /// 双击快进 / 快退的步长（秒），由调用方从设置读取
  final int Function() seekStepSeconds;

  /// 单击
  final VoidCallback onTap;

  /// 双击中间 1/3
  final VoidCallback onDoubleTapMiddle;

  /// 长按开始（倍速）
  final VoidCallback onLongPressStart;

  /// 长按结束 / 取消（恢复倍速）
  final VoidCallback onLongPressEnd;

  /// 纵向拖动调节的亮度 / 音量（null = 不接管纵向）
  final PlayerLevels? levels;

  /// 是否接管纵向拖动。短视频模式必须为 false（纵向让给 PageView 翻页）
  final bool allowVertical;

  /// 横滑拖动开始 / 结束（调用方据此显示底部进度 / 冻结控制栏自动隐藏）
  final void Function(bool active)? onScrubActiveChanged;

  /// 指针悬停（桌面端唤出控制栏）
  final void Function(PointerHoverEvent event)? onHover;

  /// 桌面端：非触摸指针拖动 = 拖动窗口（无边框播放器的主交互）
  final VoidCallback? onWindowDrag;

  /// 当前缩放值（null = 该模式不支持缩放）
  final double Function()? readZoom;

  /// 缩放值变更（绝对值）
  final void Function(double zoom)? onZoom;

  /// 缩放指示器显隐
  final void Function(bool visible)? onZoomIndicator;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  late final PlayerDragDelegate _delegate;
  late final PlayerDragGestureRecognizer _drag;
  late final TapGestureRecognizer _tap;
  late final DoubleTapGestureRecognizer _doubleTap;
  late final LongPressGestureRecognizer _longPress;
  late final SeekSession _seek;

  PointerDeviceKind _lastKind = PointerDeviceKind.touch;

  // 双指缩放
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartZoom = 1.0;

  @override
  void initState() {
    super.initState();

    _seek = SeekSession(
      readPlayer: widget.readPlayer,
      preview: seekHub.preview,
    );

    _delegate = PlayerDragDelegate()
      ..onDown = _handleDown
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragEnd;

    _drag = PlayerDragGestureRecognizer(delegate: _delegate);

    _tap = TapGestureRecognizer();
    _doubleTap = DoubleTapGestureRecognizer();
    _longPress = LongPressGestureRecognizer();
    _wireCallbacks();
  }

  @override
  void didUpdateWidget(PlayerGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 回调是每帧新建的闭包，识别器只创建一次 —— 这里把最新闭包换进去
    _wireCallbacks();
  }

  void _wireCallbacks() {
    _tap
      ..onTapDown = (details) {
        if (details.kind != null) _lastKind = details.kind!;
      }
      ..onTap = widget.onTap;

    _doubleTap.onDoubleTapDown = _handleDoubleTapDown;

    _longPress
      ..onLongPressStart = (_) {
        // 长按倍速只对触摸生效（鼠标长按不该改倍速）
        if (_lastKind != PointerDeviceKind.touch) return;
        widget.onLongPressStart();
      }
      ..onLongPressEnd = (_) => widget.onLongPressEnd();
    // 级联赋值里直接赋局部函数会被分析器报 use_of_void_result，拆开写
    _longPress.onLongPressCancel = widget.onLongPressEnd;

    _delegate
      ..allowVertical = widget.allowVertical
      ..windowDragOnNonTouch = widget.onWindowDrag != null
      ..onWindowDrag = widget.onWindowDrag;
  }

  @override
  void dispose() {
    _seek.dispose();
    _drag.dispose();
    _tap.dispose();
    _doubleTap.dispose();
    _longPress.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 拖动

  void _handleDown(Offset startGlobal, PointerDeviceKind kind) {
    _lastKind = kind;
  }

  void _handleDragStart(GestureAxis axis, Offset startGlobal) {
    if (axis == GestureAxis.horizontal) {
      // 基准 = 按下瞬间的位置快照。不能用实时位置逐帧叠加：
      // 拖动期间播放若未完全暂停，位移会被重复计入，越拖越偏。
      _seek.start(widget.readPlayer().position);
      _updateScrubHud();
      widget.onScrubActiveChanged?.call(true);
      return;
    }

    // 纵向：左半屏亮度 / 右半屏音量
    final levels = widget.levels;
    if (levels == null) return;
    final width = MediaQuery.sizeOf(context).width;
    unawaited(levels.start(left: startGlobal.dx < width / 2));
  }

  void _handleDragUpdate(GestureAxis axis, Offset globalDelta) {
    if (axis == GestureAxis.horizontal) {
      _seek.dragTo(globalDelta.dx);
      _updateScrubHud();
      return;
    }
    widget.levels?.update(dy: globalDelta.dy);
  }

  void _handleDragEnd(GestureAxis axis) {
    if (axis == GestureAxis.horizontal) {
      _seek.end();
      seekHub.hud.hideScrub();
      widget.onScrubActiveChanged?.call(false);
      return;
    }
    unawaited(widget.levels?.end() ?? Future<void>.value());
  }

  /// 拖动中的中央读数：`目标位置 / 总时长  ±增量`
  void _updateScrubHud() {
    final target = _seek.target;
    if (target == null) return;
    seekHub.hud.showScrub(
      position: _seek.base,
      target: target,
      duration: widget.readPlayer().duration,
    );
  }

  // ------------------------------------------------------------------ 双击

  void _handleDoubleTapDown(TapDownDetails details) {
    final step = widget.seekStepSeconds();
    final width = MediaQuery.sizeOf(context).width;
    final dx = details.globalPosition.dx;

    // 左 / 右 1/3 快退 / 快进，中间 1/3 播放暂停（两个模式同一套分区）
    if (dx < width / 3) {
      _stepSeek(-step);
    } else if (dx > width * 2 / 3) {
      _stepSeek(step);
    } else {
      widget.onDoubleTapMiddle();
    }
  }

  /// 双击步进：用毫秒精度的 position 直接 seek。
  ///
  /// 不再走 `MediaPlayer.forward/backward` —— 那两个是 `position.inSeconds`
  /// （秒级截断）再加减，双击 5 秒实际可能只跳 4.2 秒，且两个模式读的是
  /// 不同实例。这里统一读实时实例 + 毫秒精度 + 同一套夹取。
  void _stepSeek(int seconds) {
    final player = widget.readPlayer();
    final target = clampSeekTarget(
      player.position + Duration(seconds: seconds),
      player.duration,
    );
    unawaited(player.seek(target).catchError((_) {}));
    seekHub.hud.showStep(forward: seconds > 0, seconds: seconds.abs());
  }

  // ------------------------------------------------------------------ 指针

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.readZoom == null) return;
    _pointers[event.pointer] = event.position;
    if (_pointers.length < 2) return;

    final points = _pointers.values.toList();
    _pinchStartDistance = (points[0] - points[1]).distance;
    _pinchStartZoom = widget.readZoom!();
    // 双指按下：中断进行中的拖动，避免「缩放同时还在 seek」
    _seek.cancel();
    seekHub.hud.hideScrub();
    widget.onScrubActiveChanged?.call(false);
    unawaited(widget.levels?.end() ?? Future<void>.value());
    widget.onZoomIndicator?.call(true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (widget.readZoom == null) return;
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (_pointers.length < 2) return;

    final start = _pinchStartDistance;
    if (start == null || start <= 0) return;
    final points = _pointers.values.toList();
    final scale = (points[0] - points[1]).distance / start;
    widget.onZoom!(_pinchStartZoom * scale);
    widget.onZoomIndicator?.call(true);
  }

  void _handlePointerUp(PointerEvent event) {
    if (widget.readZoom == null) return;
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _pinchStartDistance = null;
      widget.onZoomIndicator?.call(false);
    }
  }

  /// 桌面端 Ctrl + 滚轮无级缩放（短视频模式不支持）
  void _handlePointerSignal(PointerSignalEvent event) {
    final onZoom = widget.onZoom;
    final readZoom = widget.readZoom;
    if (onZoom == null || readZoom == null) return;
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isControlPressed) return;
    final delta = -event.scrollDelta.dy / 500.0;
    if (delta == 0) return;
    onZoom(readZoom() + delta);
    widget.onZoomIndicator?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    // 屏幕宽度用于左右边缘避让（系统返回手势区）
    _delegate
      ..screenWidth = MediaQuery.sizeOf(context).width
      ..allowVertical = widget.allowVertical
      ..windowDragOnNonTouch = widget.onWindowDrag != null
      ..onWindowDrag = widget.onWindowDrag;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      onPointerSignal: _handlePointerSignal,
      onPointerHover: widget.onHover,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          PlayerDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PlayerDragGestureRecognizer>(
            () => _drag,
            (_) {},
          ),
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => _tap,
            (_) {},
          ),
          DoubleTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
            () => _doubleTap,
            (_) {},
          ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => _longPress,
            (_) {},
          ),
        },
        child: widget.child,
      ),
    );
  }
}
