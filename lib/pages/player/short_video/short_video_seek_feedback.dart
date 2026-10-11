import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// 双击快进 / 快退的瞬时提示 (方向 + 步长)。
///
/// 双击后的跳转本身没有可见反馈: 进度条在屏幕底部, 离触点很远,
/// 短视频模式下也很容易注意不到。这里在画面中央短暂显示
/// "« 5s / 5s »", 与音量 / 亮度 / 缩放等指示器同一套视觉语言
/// (黑底圆角 + 图标 + 文本)。
class ShortVideoSeekFeedbackController {
  /// 当前应显示的提示 (null = 不显示)
  final ValueNotifier<({bool forward, int seconds})?> value =
      ValueNotifier(null);

  Timer? _timer;
  int _session = 0;
  bool _disposed = false;

  /// 显示提示: [forward] 为 true 时显示快进, [seconds] 为步长 (秒)
  void show({required bool forward, required int seconds}) {
    if (_disposed) return;
    value.value = (forward: forward, seconds: seconds);
    final session = ++_session;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), () {
      // 连续双击时只收起最后一次的提示
      if (!_disposed && session == _session) {
        value.value = null;
      }
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    value.dispose();
  }
}

/// 双击快进 / 快退提示的显示层 (居中, 不拦截指针事件)
class ShortVideoSeekFeedbackOverlay extends StatelessWidget {
  const ShortVideoSeekFeedbackOverlay({super.key, required this.controller});

  final ShortVideoSeekFeedbackController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<({bool forward, int seconds})?>(
        valueListenable: controller.value,
        builder: (context, feedback, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: feedback == null
              ? const SizedBox.shrink(key: ValueKey('no-seek-feedback'))
              : Center(
                  key: ValueKey(
                    'seek-feedback-${feedback.forward}-${feedback.seconds}',
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          feedback.forward
                              ? Icons.fast_forward_rounded
                              : Icons.fast_rewind_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${feedback.forward ? '+' : '-'}${feedback.seconds}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
