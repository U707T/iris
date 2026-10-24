import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';

/// 一次拖动 seek 的会话（主窗口横滑 / 短视频横滑 / 两个模式的进度条共用）。
///
/// ## 为什么拖动中**不**实时 seek
///
/// 旧实现每 120ms 发一次 seek，看着"跟手"，实际上是拖动体验最差的一环：
/// 每次 seek 都要 flush 解码器、重新解码关键帧，连续拖动时画面反复跳变，
/// 低端机 / 网络源上直接卡成幻灯片。这也是「两个模式都调过参数还是不流畅」的根因。
///
/// 现在改成与 panelFM 一致的做法：
/// 1. **拖动中只更新预览**（[preview]），一帧解码都不做 → 拖动本身绝对流畅；
/// 2. 手指**停住** [settleDelay] 之后才真正 seek 一次，让画面跟上
///    （快速拖动时纯看数字，停下来想看哪一帧就能看到）；
/// 3. 松手时精确 seek 最终位置，按原状态续播。
///
/// 三个交互（主窗口横滑 / 短视频横滑 / 进度条拖动）走的是同一份代码，
/// 所以三个地方的手感必然一致。
class SeekSession {
  SeekSession({
    required this.readPlayer,
    required this.preview,
    this.settleDelay = const Duration(milliseconds: 350),
    this.maxSettleWait = const Duration(milliseconds: 1500),
  });

  /// 取当前实时播放器实例。
  ///
  /// 播放期间本组件不一定重建，build 时捕获的实例里 isPlaying / position
  /// 可能是过期的（先暂停再拖动会误判成「未播放」，松手后不恢复）。
  final MediaPlayer Function() readPlayer;

  /// 预览位置（由 [SeekHub] 持有，会话只写不销毁）
  final ValueNotifier<Duration?> preview;

  /// 手指停住多久之后让画面跟上（拖动中不发 seek）
  final Duration settleDelay;

  /// 松手后等播放器落定的上限（超时也要收起预览，不能把进度条冻住）
  final Duration maxSettleWait;

  Timer? _settleTimer;

  bool _alive = true;
  bool _active = false;
  bool _resume = false;
  int _session = 0;

  Duration _base = Duration.zero;
  Duration? _target;
  Duration? _pending;

  /// 最近一次真正发出去的 seek 目标（用于松手时判断画面是否已经到位）
  Duration? _lastFlushed;

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
    _pending = null;
    _lastFlushed = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    preview.value = from;
    _resume = readPlayer().isPlaying;
    if (_resume) _pauseSafely();
  }

  /// 拖动中：更新到绝对目标位置。
  ///
  /// 只写预览 + 重置「停住计时器」，不碰解码器。
  void seekTo(Duration target) {
    if (!_alive || !_active) return;
    final clamped = clampSeekTarget(target, readPlayer().duration);
    // 目标没变就不折腾（慢速拖动时同一秒内的多帧合并成一次通知）
    if (clamped == _target && _pending == null) return;
    _target = clamped;
    _pending = clamped;
    preview.value = clamped;
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, _flush);
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

  /// 手指停住了：让画面跟上当前目标（一次 seek，不是节流循环）
  void _flush() {
    _settleTimer?.cancel();
    _settleTimer = null;
    final target = _pending;
    _pending = null;
    if (target == null || !_alive || !_active) return;
    _lastFlushed = target;
    try {
      unawaited(readPlayer().seek(target).catchError((_) {}));
    } catch (_) {}
  }

  /// 松手：精确落定 -> 按原状态续播 -> 画面真的到位后再收起预览。
  void end() {
    if (!_active) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    final resume = _resume && _alive;
    final target = _target;
    final alreadyThere = target != null && target == _lastFlushed;
    _active = false;
    _resume = false;
    _pending = null;
    _lastFlushed = null;
    final session = ++_session;
    if (target == null || !_alive) {
      if (resume) _playSafely();
      preview.value = null;
      return;
    }
    if (alreadyThere) {
      // 手指停住过、画面已经跳到目标：直接续播，不要再 seek 一次
      // （重复 seek 会让画面白闪一下，是「松手不干净」的来源之一）
      if (resume) _playSafely();
      unawaited(_clearPreview(session));
      return;
    }
    unawaited(_settle(target, resume, session));
  }

  /// 中断（双指缩放 / 切模式）：与 [end] 一样落定并续播，但立即收起预览。
  void cancel() {
    if (!_active) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    final resume = _resume && _alive;
    final target = _target;
    _active = false;
    _resume = false;
    _pending = null;
    _lastFlushed = null;
    _session++;
    preview.value = null;
    if (target == null || !_alive) {
      if (resume) _playSafely();
      return;
    }
    unawaited(_seekThenPlay(target, resume));
  }

  /// 落定并等画面到位，再清预览。
  ///
  /// 为什么不是「松手立刻清预览」：seek 是异步的，播放器位置要过一会儿才更新；
  /// 立刻清会让进度条先跳回旧位置、再跳到新位置，看起来就是「松手闪一下」。
  Future<void> _settle(Duration target, bool resume, int session) async {
    await _seekThenPlay(target, resume);
    if (!_alive || session != _session) return;
    await _clearPreview(session);
  }

  /// 再等一小段让 position 流追上（mpv 的 seek 完成不等于位置事件已派发），
  /// 然后收起预览。
  Future<void> _clearPreview(int session) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (_alive && session == _session) preview.value = null;
  }

  Future<void> _seekThenPlay(Duration target, bool resume) async {
    try {
      await readPlayer().seek(target).timeout(maxSettleWait);
    } catch (_) {}
    if (!_alive) return;
    if (resume) _playSafely();
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
    _settleTimer?.cancel();
    _settleTimer = null;
    // 只有真在拖动时才需要清预览：进度条里的 disabled 实例从不 start，
    // 它们重建时不能把别处正在进行的拖动预览清掉。
    if (_active) preview.value = null;
    _active = false;
    _resume = false;
    _pending = null;
    _lastFlushed = null;
  }
}
