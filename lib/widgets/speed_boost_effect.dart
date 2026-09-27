import 'package:material_ui/material_ui.dart';

/// 长按加速 (倍速) 动效 —— 主播放界面与短视频模式通用。
///
/// 画面左右两侧各一道呼吸的白色光带, 示意"正在加速"。
/// 不用箭头 / 文字, 中央区域保持干净, 实现也保持最简。
///
/// 显示由 [visible] 控制 (自带淡入淡出), 隐藏时动画控制器会停掉, 不空转。
/// 使用方式: 放进播放画面所在的 Stack 里 (铺满画面即可, 不接收指针事件):
/// ```dart
/// Stack(
///   children: [
///     ...,
///     SpeedBoostEffect(visible: isLongPress),
///   ],
/// )
/// ```
class SpeedBoostEffect extends StatefulWidget {
  const SpeedBoostEffect({super.key, required this.visible});

  /// 是否正在长按加速 (true 亮起, false 淡出)
  final bool visible;

  /// 左右两道光带的 key (测试 / 定位用)
  static const Key leftGlowKey = ValueKey('speed-boost-left');
  static const Key rightGlowKey = ValueKey('speed-boost-right');

  @override
  State<SpeedBoostEffect> createState() => _SpeedBoostEffectState();
}

class _SpeedBoostEffectState extends State<SpeedBoostEffect>
    with SingleTickerProviderStateMixin {
  /// 光带呼吸周期 (单程)
  static const Duration _breathCycle = Duration(milliseconds: 700);

  /// 出现 / 消失的淡入淡出时长
  static const Duration _fadeDuration = Duration(milliseconds: 160);

  /// 光带尺寸与距画面边缘的留白
  static const double _glowWidth = 4;
  static const double _glowHeight = 132;
  static const double _sidePadding = 10;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: _breathCycle,
  );

  /// 亮度 (呼吸: 暗 → 亮)
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.3,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.visible) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SpeedBoostEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _breath.repeat(reverse: true);
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: _fadeDuration,
        child: widget.visible
            ? FadeTransition(
                key: const ValueKey('speed-boost'),
                opacity: _opacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _sidePadding,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _glow(SpeedBoostEffect.leftGlowKey),
                      _glow(SpeedBoostEffect.rightGlowKey),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('no-speed-boost')),
      ),
    );
  }

  /// 一道光带: 中间亮、两端渐隐, 外圈带一层柔光
  Widget _glow(Key key) {
    return Container(
      key: key,
      width: _glowWidth,
      height: _glowHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.6),
            blurRadius: 16,
          ),
        ],
      ),
    );
  }
}
