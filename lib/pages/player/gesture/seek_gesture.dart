/// 播放器手势的公共参数与换算（主窗口 / 短视频模式共用一套）。
///
/// 以前两套代码各写各的：
/// - 主窗口：`abs(dx) > abs(dy)` 直接锁方向、8px 死区、3px/秒、秒级粒度；
/// - 短视频：Flutter 自带的 horizontal drag（约 18px 才进入）、3px/秒、毫秒粒度；
/// 结果是「同样的手指动作，两个模式的手感不一样」。
///
/// 这里把参数与判定收敛成纯函数（不依赖 Flutter），可直接单测：
/// - 死区 [kGestureDeadZoneDp]：位移没超过它时**保持未定态**，什么都不做；
/// - 主轴优势比 [kGestureAxisBias]：某一轴必须明显占优才锁定方向，斜滑保持未定，
///   避免「横滑到一半变成调音量」这种跳变（照 panelFM 的 MtGesture.playerAxis）；
/// - 灵敏度 [kSeekPixelsPerSecond]：与屏幕尺寸无关的固定物理量（3px = 1 秒）。
library;

/// 拖动 seek 的灵敏度：每滑动多少逻辑像素代表 1 秒（主窗口 / 短视频 / 进度条同一口径）。
const double kSeekPixelsPerSecond = 3.0;

/// 手势进入死区（dp）：位移没超过它时不做方向判定。
const double kGestureDeadZoneDp = 8.0;

/// 主轴优势比：占优的那一轴至少是另一轴的这么多倍，才锁定方向。
const double kGestureAxisBias = 1.4;

/// 屏幕左右边缘避让（逻辑像素）：这块区域属于系统返回手势，不参与播放器手势。
const double kGestureEdgeDeadZone = 48.0;

/// 手势方向判定结果。
enum GestureAxis {
  /// 横向：调节播放进度
  horizontal,

  /// 纵向：左侧亮度 / 右侧音量
  vertical,
}

/// 判定播放器手势方向。
///
/// 返回 null 表示**未定**：没超过死区，或者斜滑（两轴势均力敌）——
/// 此时调用方应保持原状，等用户意图清晰再锁定，而不是猜一个方向。
GestureAxis? resolveGestureAxis({
  required double dxDp,
  required double dyDp,
  double deadZoneDp = kGestureDeadZoneDp,
  double axisBias = kGestureAxisBias,
}) {
  final ax = dxDp.abs();
  final ay = dyDp.abs();
  if (ax < deadZoneDp && ay < deadZoneDp) return null;
  if (ax > ay * axisBias) return GestureAxis.horizontal;
  if (ay > ax * axisBias) return GestureAxis.vertical;
  return null;
}

/// 把目标位置夹到 `[0, duration]` 区间（duration 未知时只夹下界）。
Duration clampSeekTarget(Duration target, Duration duration) {
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// 由「基准位置 + 横向位移」算出 seek 目标。
///
/// [dxPixels] 是相对**按下点**的累计横向位移（正 = 快进），不是每帧增量：
/// 用累计位移换算才不会随帧率漂移，松手落点也与手指位置一致。
Duration seekTargetFor({
  required Duration base,
  required double dxPixels,
  required Duration duration,
}) {
  final deltaMs = (dxPixels / kSeekPixelsPerSecond * 1000).round();
  return clampSeekTarget(base + Duration(milliseconds: deltaMs), duration);
}

/// 位移 → 时间增量（用于提示文本 / 日志）。
Duration seekDeltaFor(double dxPixels) =>
    Duration(milliseconds: (dxPixels / kSeekPixelsPerSecond * 1000).round());
