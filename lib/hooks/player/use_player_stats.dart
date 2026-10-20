import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:media_kit/media_kit.dart';

/// 播放统计轮询（帧率 / 丢帧 / 解码器 / 像素格式 / 缓存速度）。
///
/// media_kit 的属性读取是异步的，界面不能直接 await；这里用定时器把结果
/// 刷进一个 ref，返回**同步读取函数**给 UI 用（与原来的行为一致）。
/// 只有 [isShowStats] 打开时才启动定时器，关闭即停。
Map<String, String> Function() usePlayerStats(
  Player player, {
  required bool isShowStats,
}) {
  final stats = useRef<Map<String, String>?>(null);
  final timer = useRef<Timer?>(null);

  useEffect(() {
    Future<void> refresh() async {
      try {
        final nativePlayer = player.platform;
        if (nativePlayer is! NativePlayer) return;

        final results = <String, String>{};

        Future<void> read(String key, String property) async {
          try {
            final value = await nativePlayer.getProperty(
              property,
              waitForInitialization: false,
            );
            if (value.isNotEmpty && value != 'no') {
              results[key] = value;
            }
          } catch (_) {}
        }

        await read('fps', 'estimated-vf-fps');
        await read('drops', 'frame-drop-count');
        await read('decoder', 'hwdec-current');
        await read('pixfmt', 'video-format');
        await read('cache', 'cache-speed');

        if (results.isNotEmpty) {
          stats.value = results;
        }
      } catch (_) {}
    }

    timer.value?.cancel();
    // 仅在需要时启用, 每秒刷新一次
    if (isShowStats) {
      timer.value = Timer.periodic(
        const Duration(seconds: 1),
        (_) => refresh(),
      );
      refresh();
    }
    return () => timer.value?.cancel();
  }, [isShowStats]);

  return () => stats.value ?? const {};
}
