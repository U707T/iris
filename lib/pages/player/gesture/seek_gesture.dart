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
/// - 幅度 [seekSpanPerScreen]：**滑过一屏宽 = 跳转多长时间**，按片长自适应并封顶 6 分钟
///   （口径见 [kSeekSpanPerScreen]，与 panelFM 的实机幅度一致）。
library;

/// 横滑 seek 的幅度：**滑过一屏宽**对应的时间跨度（主窗口 / 短视频 / 全平台同一口径）。
///
/// 为什么按「一屏宽」而不是「每像素多少秒」：手感只与「手指划过屏幕的比例」有关。
/// 按每像素算，换个设备（手机 / 平板 / 桌面宽窗口）同一段手势走过去的时间就不一样了。
///
/// 取值依据（v2.6.3 修正，「滑半天只走一点点」的根因）：
/// - panelFM 实机口径是 3 **物理**像素 = 1 秒（`MtGesture.PlayerSeekPxPerSecond` 收到的
///   是 Compose 的 px），1080p 手机一屏 1080px ≈ **360 秒**；
/// - IRIS 此前把同一个数字用在**逻辑**像素上（3dp = 1 秒），一屏 393dp 只有 131 秒 ——
///   幅度只有 panelFM 的 1/3；
/// - 但短片段不能直接吃 6 分钟/屏：30 秒的片段若按 6 分钟算，手指挪 30dp 就到头了。
///   所以短片按**片长**算（一屏宽 = 全长，与 YouTube / 主流短视频的滚动一致），
///   只有长片才用满这个封顶值。
const Duration kSeekSpanPerScreen = Duration(minutes: 6);

/// 屏幕宽度未知时的兜底灵敏度：1 逻辑像素（dp）= 1 秒。
///
/// 等于「393dp 手机 × 6 分钟/屏」的换算值，只在拿不到宽度时使用（单测 / 首帧）。
const double kSeekFallbackMsPerPixel = 1000.0;

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

/// 一屏宽的横滑对应多长时间：短片 = 全长，长片 = [kSeekSpanPerScreen]。
///
/// [duration] 未知（0）时按长片处理，退回封顶值 —— 拖动开始时片长一定是已知的。
Duration seekSpanPerScreen(Duration duration) =>
    duration > Duration.zero && duration < kSeekSpanPerScreen
        ? duration
        : kSeekSpanPerScreen;

/// 横滑灵敏度：每逻辑像素代表多少毫秒。
///
/// [screenWidth] 是滑动手势所在区域的宽度（逻辑像素），[duration] 是当前片长。
/// 宽度未知（<= 0）时退回 [kSeekFallbackMsPerPixel]。
double seekMsPerPixel({
  required Duration duration,
  double screenWidth = 0,
}) =>
    screenWidth > 0
        ? seekSpanPerScreen(duration).inMilliseconds / screenWidth
        : kSeekFallbackMsPerPixel;

/// 由「基准位置 + 横向位移」算出 seek 目标。
///
/// [dxPixels] 是相对**按下点**的累计横向位移（正 = 快进），不是每帧增量：
/// 用累计位移换算才不会随帧率漂移，松手落点也与手指位置一致。
Duration seekTargetFor({
  required Duration base,
  required double dxPixels,
  required Duration duration,
  double screenWidth = 0,
}) {
  final deltaMs =
      (dxPixels * seekMsPerPixel(duration: duration, screenWidth: screenWidth))
          .round();
  return clampSeekTarget(base + Duration(milliseconds: deltaMs), duration);
}

/// 位移 → 时间增量（用于提示文本 / 日志）。
Duration seekDeltaFor(
  double dxPixels, {
  required Duration duration,
  double screenWidth = 0,
}) =>
    Duration(
      milliseconds:
          (dxPixels * seekMsPerPixel(duration: duration, screenWidth: screenWidth))
              .round(),
    );
