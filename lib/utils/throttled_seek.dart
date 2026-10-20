/// 拖动 seek 节流器（主界面横向拖动 / 短视频 scrub 共用）。
///
/// 不节流时每个 pointer move 都会发一条 seek: mpv 在低端机 / 网络源上
/// 会卡顿、画面回跳。规则:
/// - 第一次 seek 立即发送（跟手）
/// - 拖动中最多每 [interval] 发一次
/// - 松手时补发最终位置（精确落点）
class ThrottledSeek {
  ThrottledSeek({
    required this.seekTo,
    this.interval = const Duration(milliseconds: 120),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final void Function(Duration target) seekTo;
  final Duration interval;

  /// 时钟注入（测试用）
  final DateTime Function() _now;

  DateTime? _lastAt;
  Duration? _pending;
  bool _active = false;

  bool get isActive => _active;

  /// 开始一次拖动（重复调用无副作用）
  void begin() {
    if (_active) return;
    _active = true;
    _lastAt = null;
    _pending = null;
  }

  /// 拖动中：记录目标位置，按节流间隔发送
  void seek(Duration target) {
    if (!_active) return;
    _pending = target;

    final now = _now();
    final last = _lastAt;
    if (last == null || now.difference(last) >= interval) {
      _flush(now);
    }
  }

  /// 结束拖动：补发最终位置
  void end() {
    if (!_active) return;
    final pending = _pending;
    _active = false;
    _pending = null;
    _lastAt = null;
    if (pending != null) seekTo(pending);
  }

  void _flush(DateTime now) {
    final target = _pending;
    if (target == null) return;
    _lastAt = now;
    seekTo(target);
  }
}
