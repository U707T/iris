import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';
import 'package:iris/utils/throttled_seek.dart';

/// 一次拖动 seek 的会话（主窗口横滑 / 短视频横滑 / 短视频进度条共用）。
///
/// 之前主窗口和短视频是两套实现，行为不一样，也正是「体验割裂」的来源：
/// - 主窗口：拖动期间**不暂停**，每 120ms 发一次 seek，画面一边播一边跳；
///   没有预览值，进度条只能等播放器回调，永远慢半拍。
/// - 短视频：暂停 + 本地预览 + 节流，但没有画面中央的读数。
///
/// 现在统一成同一份规则：
/// 1. 开始拖动就暂停（原本在播才恢复），松手精确 seek 后按原状态续播；
/// 2. [preview] 本地预览值让进度条 / 提示实时跟手，不等播放器回调
///    （主窗口与短视频都写同一个 [SeekHub.preview]）；
/// 3. 预览 seek 走 [ThrottledSeek]（第一次立即发送、拖动中节流、松手补发最终位置）；
/// 4. 起手不发无意义的 seek（旧实现在 start 时先 seek 到当前位置，会顿一下）。
class SeekSession {
  SeekSession({
    required this.readPlayer,
    required this.preview,
    DateTime Function()? clock,
    Duration interval = const Duration(milliseconds: 120),
    Duration previewHold = const Duration(milliseconds: 600),
  })  : _previewHold = previewHold,
        _throttle = ThrottledSeek(
          seekTo: (target) => readPlayer().seek(target),
          interval: interval,
          clock: clock,
        );

  /// 取当前实时播放器实例。
  ///
  /// 播放期间本组件不一定重建，build 时捕获的实例里 isPlaying / position
  /// 可能是过期的（先暂停再拖动会误判成「未播放」，松手后不恢复）。
  final MediaPlayer Function() readPlayer;

  /// 预览位置（由 [SeekHub] 持有，会话只写不销毁）
  final ValueNotifier<Duration?> preview;

  /// 松手后预览值保留时长（避免松手瞬间进度先回跳再跳）
  final Duration _previewHold;

  final ThrottledSeek _throttle;

  bool _alive = true;
  bool _active = false;
  bool _resume = false;
  int _session = 0;

  Duration _base = Duration.zero;
  Duration? _target;

  /// 是否正处于一次拖动中
  bool get isActive => _active;

  /// 本次拖动的基准位置（按下瞬间的播放位置）
  Duration get base => _base;

  /// 当前目标位置（拖动中 = 手指指向的位置）
  Duration? get target => _target;

  /// 开始拖动前是否在播放（决定松手后要不要续播）
  bool get wasPlaying => _resume;

  /// 开始拖动。[from] 为按下瞬间的播放位置。
  ///
  /// 只记录基准与预览，**不发 seek**：手指还没动，没有要跳的目标。
  void start(Duration from) {
    if (!_alive) return;
    _session++;
    _active = true;
    _base = from;
    _target = from;
    preview.value = from;
    _resume = readPlayer().isPlaying;
    if (_resume) _pauseSafely();
    _throttle.begin();
  }

  /// 拖动中：更新到绝对目标位置（节流 seek，预览立即跟手）。
  void seekTo(Duration target) {
    if (!_alive || !_active) return;
    final clamped = clampSeekTarget(target, readPlayer().duration);
    _target = clamped;
    preview.value = clamped;
    _throttle.seek(clamped);
  }

  /// 拖动中：按相对按下点的累计横向位移更新目标（正 = 快进）。
  void dragTo(double dxPixels) {
    if (!_alive || !_active) return;
    seekTo(seekTargetFor(
      base: _base,
      dxPixels: dxPixels,
      duration: readPlayer().duration,
    ));
  }

  /// 松手：补发最终位置、按原状态续播，预览保留一小段时间后收起。
  void end() {
    if (!_active) return;
    final resume = _resume && _alive;
    _active = false;
    _resume = false;
    final session = ++_session;
    _throttle.end();
    if (resume) _playSafely();
    Future<void>.delayed(_previewHold, () {
      if (_alive && session == _session) preview.value = null;
    });
  }

  /// 中断（双指缩放 / 组件销毁）：与 [end] 一样落定并续播，但立即收起预览。
  void cancel() {
    if (!_active) return;
    end();
    _session++;
    preview.value = null;
  }

  void _pauseSafely() {
    try {
      unawaited(readPlayer().pause().catchError((_) {}));
    } catch (_) {}
  }

  void _playSafely() {
    try {
      unawaited(readPlayer().play().catchError((_) {}));
    } catch (_) {}
  }

  void dispose() {
    _alive = false;
    // 切模式 / 关页面时若还在拖动，共享预览会残留到另一个模式，
    // 表现为「新模式的进度条冻在旧位置」——这里必须清掉。
    if (preview.value != null) preview.value = null;
    _active = false;
    _resume = false;
  }
}
