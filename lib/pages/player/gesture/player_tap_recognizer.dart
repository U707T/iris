import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// 单击 / 双击判定（主窗口与短视频模式共用）。
///
/// ## 为什么不用 Flutter 自带的 Tap + DoubleTap 组合
///
/// 把一个 `TapGestureRecognizer` 和一个 `DoubleTapGestureRecognizer` 放进同一个
/// 竞技场时，单击必须等双击窗口走完才能确认 —— 实测（`flutter_test`：
/// 同时注册两者，单击在 **300ms** 后才触发，即 `kDoubleTapTimeout`；只注册
/// Tap 时 10ms 就触发）。表现就是「点一下画面，小半秒后控制栏才出来」。
///
/// ## 单击什么时候可以「立即」
///
/// 由 [deferSingleTap] 决定（每次求值，可以看当前状态）：
///
/// - 返回 false：指针抬起就**立即**回调 [onTap]。控制栏「唤出」是无损动作，
///   双击时第一下顺带把控制栏叫出来完全可接受 —— YouTube / PotPlayer / mpv
///   都是这样立刻响应的。
/// - 返回 true：等双击窗口结束再确认。用于两类单击：
///   1. 有副作用的单击（短视频的「播放 / 暂停」：立即执行会让双击中间 1/3
///      先暂停再播放，能听见一次多余停顿）；
///   2. 主窗口的「收起控制栏」—— 唤起要快，收起晚 300ms 无感，
///      却换来了「双击快进不会顺手把控制栏收掉」。
///
/// 拖动 / 长按仍由各自的识别器赢走竞技场：位移超过 [kTapSlopDp] 时本识别器主动
/// 弃权；按得够久（≥ 长按识别器的 500ms 窗口）时长按先赢走竞技场，本识别器被
/// 判负 —— 所以这里**不需要**再设一个按压时长上限，设了反而会把 300~500ms 的
/// 「慢一点」吞掉。
///
/// 双击窗口用 `Timer` 而不是用 `PointerEvent.timeStamp` 相减：时间戳在部分平台
/// （以及 `flutter_test` 的合成事件）上是常量或精度很粗，靠减法判窗口会失效；
/// Flutter 官方的 `DoubleTapGestureRecognizer` 也是用计时器控制窗口的。
class PlayerTapGestureRecognizer extends OneSequenceGestureRecognizer {
  PlayerTapGestureRecognizer({
    super.debugOwner,
    bool Function()? deferSingleTap,
    this.doubleTapWindow = kDoubleTapWindow,
  }) : _deferSingleTap = deferSingleTap;

  /// 这次单击是否要推迟到双击窗口结束后再触发（见类说明）。
  /// null = 永不推迟（单击第一时间响应）。
  ///
  /// 识别器只创建一次，判定条件却可能随状态变化（控制栏此刻是显示还是收起），
  /// 所以这里是可写字段：`_wireCallbacks` 每帧把最新的闭包换进来。
  bool Function()? _deferSingleTap;

  /// 当前这次单击是否需要推迟
  bool get deferSingleTap => _deferSingleTap?.call() ?? false;

  set deferSingleTap(bool Function()? value) => _deferSingleTap = value;

  /// 双击窗口（两次抬起的最大间隔）
  final Duration doubleTapWindow;

  /// 单击
  VoidCallback? onTap;

  /// 双击（第二下抬起时触发），参数是抬起位置（用于左 / 中 / 右分区判定）
  void Function(Offset globalPosition)? onDoubleTap;

  int? _pointer;
  Offset _downPosition = Offset.zero;

  /// 上一次点击的落点 + 双击窗口计时器
  Offset? _lastTapPosition;
  Timer? _doubleTapTimer;

  /// 推迟中的单击（[deferSingleTap] 时使用）
  Offset? _pendingPosition;
  Timer? _pendingTimer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // 已经有一根手指在跟：额外手指不参与（双指缩放由外层 Listener 处理）
    if (_pointer != null) {
      startTrackingPointer(event.pointer, event.transform);
      resolvePointer(event.pointer, GestureDisposition.rejected);
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      // 点击时手指会有 1~2px 抖动，超过阈值就让位给拖动识别器
      if ((event.position - _downPosition).distance > kTapSlopDp) _reject();
      return;
    }

    if (event is PointerUpEvent) {
      final distance = (event.position - _downPosition).distance;
      if (distance > kTapSlopDp) {
        _reject();
        return;
      }
      resolve(GestureDisposition.accepted);
      _handleTapUp(event.position);
      _finish();
      return;
    }

    if (event is PointerCancelEvent) _reject();
  }

  void _handleTapUp(Offset position) {
    final lastPosition = _lastTapPosition;
    final bool isSecondTap = lastPosition != null &&
        (_doubleTapTimer?.isActive ?? false) &&
        (position - lastPosition).distance <= kDoubleTapSlopDp;

    if (isSecondTap) {
      // 第二下：撤销「待确认的单击」，只发双击
      _cancelPendingTap();
      _stopDoubleTapWindow();
      onDoubleTap?.call(position);
      return;
    }

    if (deferSingleTap) {
      _pendingPosition = position;
      _pendingTimer?.cancel();
      _pendingTimer = Timer(doubleTapWindow, () {
        _pendingTimer = null;
        final pending = _pendingPosition;
        _pendingPosition = null;
        if (pending != null) onTap?.call();
      });
    } else {
      onTap?.call();
    }

    // 开一个新的双击窗口，等可能的第二下
    _lastTapPosition = position;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(doubleTapWindow, () {
      _doubleTapTimer = null;
      _lastTapPosition = null;
    });
  }

  void _stopDoubleTapWindow() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _lastTapPosition = null;
  }

  void _cancelPendingTap() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingPosition = null;
  }

  void _reject() {
    resolve(GestureDisposition.rejected);
    _finish();
  }

  void _finish() {
    final pointer = _pointer;
    _pointer = null;
    if (pointer != null) stopTrackingPointer(pointer);
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    // 拖动 / 长按赢了：不触发单击，同时清掉双击配对，
    // 免得「长按松手之后紧随的一下点击」被误判成双击
    _cancelPendingTap();
    _stopDoubleTapWindow();
    _finish();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
  }

  @override
  void dispose() {
    _cancelPendingTap();
    _stopDoubleTapWindow();
    super.dispose();
  }

  @override
  String get debugDescription => 'player tap';
}

/// 单击允许的最大位移（dp）：超过就当成拖动
const double kTapSlopDp = 18.0;

/// 双击窗口（两次抬起的间隔）
const Duration kDoubleTapWindow = Duration(milliseconds: 300);

/// 双击允许的两次落点距离（dp）
const double kDoubleTapSlopDp = 60.0;
