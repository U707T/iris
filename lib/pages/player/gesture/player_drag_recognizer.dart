import 'package:flutter/gestures.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';

/// 播放器拖动识别器的对外依赖。
///
/// 为什么用「委托对象 + 可写字段」而不是构造时传闭包：
/// 识别器由 `RawGestureDetector` 缓存、只创建一次，而闭包每一帧都是新的。
/// 把回调写进这个稳定对象里，识别器每次事件读到的都是最新的处理器，
/// 不需要为了刷新闭包而重建识别器（重建会打断进行中的手势）。
class PlayerDragDelegate {
  /// 屏幕宽度（逻辑像素），用于左右边缘避让
  double screenWidth = 0.0;

  /// 是否参与手势（例如正在双指缩放时关掉）
  bool enabled = true;

  /// 是否接管纵向拖动。
  /// 短视频模式交给 PageView 翻页，这里必须为 false（纵向直接拒绝，让下层赢）。
  bool allowVertical = true;

  /// 桌面端：非触摸指针的拖动用于拖动窗口（无边框播放器的主交互）
  bool windowDragOnNonTouch = false;

  /// 手指按下（还没超过死区）
  void Function(Offset startGlobal, PointerDeviceKind kind)? onDown;

  /// 方向锁定，开始拖动
  void Function(GestureAxis axis, Offset startGlobal)? onStart;

  /// 拖动中：[globalDelta] 是相对按下点的累计位移
  void Function(GestureAxis axis, Offset globalDelta)? onUpdate;

  /// 松手（只有真正开始拖动过才会回调）
  void Function(GestureAxis axis)? onEnd;

  /// 中断（来电、系统手势抢占等）
  void Function(GestureAxis axis)? onCancel;

  /// 桌面端「开始拖窗口」（只在越过死区后触发一次）
  void Function()? onWindowDrag;
}

/// 播放器拖动识别器（主窗口 / 短视频模式共用）。
///
/// 与 Flutter 自带 `HorizontalDragGestureRecognizer` 的区别，也是手感割裂的根源：
/// - 自带识别器只看「主轴位移 > touchSlop（约 18px）」，斜滑也直接进入，
///   短视频里表现为「想上下翻页却先把进度拖了一下」；
/// - 这里用 [resolveGestureAxis]：8dp 死区 + 1.4 倍主轴优势比，方向不明确时**保持未定**，
///   于是「横滑 = 进度」「竖滑 = 音量 / 翻页」永远不会互相抢。
///
/// 注意：Flutter 的位置都是逻辑像素，1 逻辑像素 == 1 dp，位移可直接当 dp 用。
class PlayerDragGestureRecognizer extends OneSequenceGestureRecognizer {
  PlayerDragGestureRecognizer({required this.delegate, super.debugOwner});

  final PlayerDragDelegate delegate;

  int? _pointer;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _startGlobal = Offset.zero;
  GestureAxis? _axis;
  bool _accepted = false;
  bool _windowDragStarted = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // 已经有一根手指在跟：额外手指不参与拖动（双指缩放由外层 Listener 处理）
    if (_pointer != null) {
      startTrackingPointer(event.pointer, event.transform);
      resolvePointer(event.pointer, GestureDisposition.rejected);
      return;
    }
    if (!delegate.enabled) return;

    // 屏幕左右边缘属于系统返回手势区：完全不参与，免得「边缘滑不动」
    if (event.kind == PointerDeviceKind.touch &&
        delegate.screenWidth > 0 &&
        (event.position.dx < kGestureEdgeDeadZone ||
            event.position.dx > delegate.screenWidth - kGestureEdgeDeadZone)) {
      return;
    }

    _pointer = event.pointer;
    _kind = event.kind;
    _startGlobal = event.position;
    _axis = null;
    _accepted = false;
    _windowDragStarted = false;
    startTrackingPointer(event.pointer, event.transform);
    delegate.onDown?.call(_startGlobal, event.kind);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      _handleMove(event);
      return;
    }

    if (event is PointerUpEvent) {
      if (_accepted && !_windowDragStarted) delegate.onEnd?.call(_axis!);
      _finish();
      return;
    }

    if (event is PointerCancelEvent) {
      if (_accepted && !_windowDragStarted) delegate.onCancel?.call(_axis!);
      _finish();
    }
  }

  void _handleMove(PointerMoveEvent event) {
    final delta = event.position - _startGlobal;

    // 桌面端鼠标 / 触控板：越过死区就是「拖窗口」，不再参与播放器手势
    if (delegate.windowDragOnNonTouch &&
        _kind != PointerDeviceKind.touch &&
        !_windowDragStarted) {
      if (delta.distance < kGestureDeadZoneDp) return;
      _windowDragStarted = true;
      _accepted = true;
      resolve(GestureDisposition.accepted);
      delegate.onWindowDrag?.call();
      return;
    }
    if (_windowDragStarted) return;

    if (!_accepted) {
      final axis = resolveGestureAxis(dxDp: delta.dx, dyDp: delta.dy);
      // 未定态：继续等，什么都不做（不猜方向、不抢手势）
      if (axis == null) return;

      if (axis == GestureAxis.vertical && !delegate.allowVertical) {
        // 纵向留给下层（短视频的 PageView 翻页）
        _reject();
        return;
      }

      _axis = axis;
      _accepted = true;
      resolve(GestureDisposition.accepted);
      delegate.onStart?.call(axis, _startGlobal);
    }

    delegate.onUpdate?.call(_axis!, delta);
  }

  void _reject() {
    resolve(GestureDisposition.rejected);
    _finish();
  }

  void _finish() {
    final pointer = _pointer;
    _pointer = null;
    _axis = null;
    _accepted = false;
    _windowDragStarted = false;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {
    // 由「其他成员都拒绝后的兜底胜出」拿到手势时，说明用户只是点了一下：
    // 没有锁定方向就不该被当成拖动，回调一律不发。
    if (_axis == null && !_windowDragStarted) _finish();
  }

  @override
  void rejectGesture(int pointer) {
    _finish();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _axis = null;
    _accepted = false;
    _windowDragStarted = false;
  }

  @override
  String get debugDescription => 'player drag';
}
