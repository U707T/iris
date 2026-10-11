import 'package:flutter/gestures.dart';

/// 短视频模式的鼠标滚轮切换逻辑 (接管 PageView 默认的滚轮翻页)。
///
/// 增量处理: 累积到阈值再切换 —— 标准滚轮一格约 33~100px (取决于系统
/// "每次滚动几行": 行数 × 100/3), 单次事件即达阈值; 高精度滚轮 / 远程桌面
/// 的细粒度增量则逐次累积 (此前直接丢弃 <4px 的增量, 导致这类设备上滚轮
/// 完全没有反应)。
///
/// 注册点建议两处, 缺一不可:
/// - PageView 页面内的 Listener: 位于 PageView 内部, 会先于 Scrollable
///   拿到事件, 屏蔽其默认的滚轮翻页;
/// - 根部 Listener: 底部信息栏 / 按钮等覆盖层会吸收命中测试,
///   指针在这些区域滚动时只有根部 Listener 能收到事件。
class ShortVideoWheelSwitcher {
  ShortVideoWheelSwitcher({required this.onSwitch, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// 切换回调: 上一条 -1 / 下一条 +1
  final void Function(int direction) onSwitch;

  /// 时钟注入 (测试用)
  final DateTime Function() _now;

  /// 累积阈值 (逻辑像素)
  static const double threshold = 30.0;

  /// 两次滚轮事件间隔超过该值视为新的滚动动作, 累积重新计数。
  static const Duration gestureGap = Duration(milliseconds: 400);

  /// 两次切换之间的最小间隔 (避免快速滚动一次跳过太多视频)。
  static const Duration switchCooldown = Duration(milliseconds: 420);

  double _accumulator = 0.0;
  DateTime? _lastSwitchAt;
  DateTime? _lastEventAt;

  /// 在 onPointerSignal 中调用
  void register(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scrollEvent = resolved as PointerScrollEvent;
      handleScroll(scrollEvent.scrollDelta.dy);
    });
  }

  /// 处理一次滚轮增量 (注册逻辑的核心, 拆出来便于单测)
  void handleScroll(double dy) {
    if (dy == 0) return;
    final now = _now();

    // 冷却期内直接丢弃, 避免快速滚动一次跳过太多视频
    final lastSwitch = _lastSwitchAt;
    if (lastSwitch != null &&
        now.difference(lastSwitch) < switchCooldown) {
      _accumulator = 0;
      return;
    }

    // 间隔过久视为新的滚动动作; 反向滚动也从当前增量重新开始累积
    final lastEventAt = _lastEventAt;
    if (lastEventAt == null || now.difference(lastEventAt) > gestureGap) {
      _accumulator = 0;
    }
    _lastEventAt = now;
    final accumulated = _accumulator;
    _accumulator = accumulated == 0 || accumulated.sign == dy.sign
        ? accumulated + dy
        : dy;

    if (_accumulator.abs() < threshold) return;
    final direction = _accumulator > 0 ? 1 : -1;
    _accumulator = 0;
    _lastSwitchAt = now;
    onSwitch(direction);
  }
}
