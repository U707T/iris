import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';

/// 快进 / 快退提示的种类。
enum SeekHudKind {
  /// 双击：一次固定步长的快进 / 快退（显示 `+5s`）
  step,

  /// 拖动：手指指向的目标位置（显示 `01:23 → 03:45 / 10:00`）
  scrub,
}

/// 提示内容（不可变，方便 ValueNotifier 直接比较）。
@immutable
class SeekHudState {
  const SeekHudState.step({required this.forward, required this.seconds})
      : kind = SeekHudKind.step,
        position = null,
        target = null,
        duration = Duration.zero;

  const SeekHudState.scrub({
    required this.position,
    required this.target,
    required this.duration,
  })  : kind = SeekHudKind.scrub,
        forward = true,
        seconds = 0;

  final SeekHudKind kind;

  /// step: 是否快进
  final bool forward;

  /// step: 步长（秒）
  final int seconds;

  /// scrub: 按下瞬间的位置
  final Duration? position;

  /// scrub: 手指指向的目标位置
  final Duration? target;

  /// scrub: 总时长
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is SeekHudState &&
      other.kind == kind &&
      other.forward == forward &&
      other.seconds == seconds &&
      other.position == position &&
      other.target == target &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(kind, forward, seconds, position, target, duration);
}

/// 快进 / 快退提示的状态机（主窗口与短视频模式共用同一份）。
///
/// 以前只有短视频模式有「双击 +5s」的中央提示，主窗口只有底部一条细进度线；
/// 而拖动时两边都没有「当前位置 → 目标位置」的读数，滑多少全靠猜。
///
/// - [showStep] 双击用，[stepHold] 后自动收起；
/// - [showScrub] 拖动用，持续显示直到 [hideScrub]（松手时调用）；
/// - 连续操作以最后一次为准（session 计数，旧定时器不会把新提示收掉）。
class SeekHudController {
  SeekHudController({this.stepHold = const Duration(milliseconds: 700)});

  /// 双击提示的显示时长
  final Duration stepHold;

  /// 当前应显示的提示（null = 不显示）
  final ValueNotifier<SeekHudState?> value = ValueNotifier(null);

  Timer? _timer;
  int _session = 0;
  bool _disposed = false;

  /// 双击快进 / 快退的瞬时提示
  void showStep({required bool forward, required int seconds}) {
    if (_disposed) return;
    value.value = SeekHudState.step(forward: forward, seconds: seconds);
    final session = ++_session;
    _timer?.cancel();
    _timer = Timer(stepHold, () {
      // 连续双击时只收起最后一次的提示
      if (!_disposed && session == _session) value.value = null;
    });
  }

  /// 拖动中的位置读数（不自动收起，跟随手指）
  void showScrub({
    required Duration position,
    required Duration target,
    required Duration duration,
  }) {
    if (_disposed) return;
    _timer?.cancel();
    _session++;
    value.value = SeekHudState.scrub(
      position: position,
      target: target,
      duration: duration,
    );
  }

  /// 松手：收起拖动读数
  void hideScrub() {
    if (_disposed) return;
    if (value.value?.kind != SeekHudKind.scrub) return;
    _session++;
    value.value = null;
  }

  void clear() {
    _timer?.cancel();
    _session++;
    if (!_disposed) value.value = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    value.dispose();
  }
}

/// 快进 / 快退提示层（画面中央，不拦截指针事件）。
///
/// 视觉与音量 / 亮度指示器同一套语言：黑底圆角胶囊 + 图标 + 文本。
class SeekHudOverlay extends StatelessWidget {
  const SeekHudOverlay({super.key, required this.controller});

  final SeekHudController controller;

  static const TextStyle _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<SeekHudState?>(
        valueListenable: controller.value,
        builder: (context, state, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: state == null
              ? const SizedBox.shrink(key: ValueKey('no-seek-hud'))
              : Center(
                  key: ValueKey(
                    state.kind == SeekHudKind.step
                        ? 'seek-hud-step-${state.forward}-${state.seconds}'
                        : 'seek-hud-scrub-${state.target?.inMilliseconds}',
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: state.kind == SeekHudKind.step
                          ? _stepChildren(state)
                          : _scrubChildren(state),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _stepChildren(SeekHudState state) => [
        Icon(
          state.forward
              ? Icons.fast_forward_rounded
              : Icons.fast_rewind_rounded,
          color: Colors.white,
          size: 24,
        ),
        const SizedBox(width: 10),
        Text(
          '${state.forward ? '+' : '-'}${state.seconds}s',
          style: _textStyle,
        ),
      ];

  List<Widget> _scrubChildren(SeekHudState state) {
    final position = state.position ?? Duration.zero;
    final target = state.target ?? position;
    final forward = target >= position;
    final delta = (target - position).abs();
    return [
      Icon(
        forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
        color: Colors.white,
        size: 24,
      ),
      const SizedBox(width: 10),
      Text(
        '${formatDurationToMinutes(target)} / ${formatDurationToMinutes(state.duration)}',
        style: _textStyle,
      ),
      const SizedBox(width: 10),
      Text(
        '${forward ? '+' : '-'}${_shortDelta(delta)}',
        style: _textStyle.copyWith(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    ];
  }

  /// 拖动读数里的增量：不足 1 分钟显示秒，超过显示 `1:23`。
  static String _shortDelta(Duration delta) {
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    return formatDurationToMinutes(delta);
  }
}
