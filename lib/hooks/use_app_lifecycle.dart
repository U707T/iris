import 'dart:async';
import 'dart:ui';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:iris/utils/logger.dart';
import 'package:provider/provider.dart';

void useAppLifecycle() {
  final context = useContext();

  AppLifecycleState? appLifecycleState = useAppLifecycleState();

  useEffect(() {
    if (appLifecycleState == null) return null;

    // paused: 移动端切后台 / 锁屏
    // hidden / detached: 桌面最小化、引擎退出 —— 桌面没有 paused,
    // 只认 paused 会让"最小化后直接关机"丢掉这段进度。
    const saveStates = {
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    };
    if (!saveStates.contains(appLifecycleState)) return null;

    logger('App lifecycle state: $appLifecycleState');
    try {
      unawaited(context.read<MediaPlayer>().saveProgress());
    } catch (e) {
      logger('App lifecycle state error: $e');
    }
    return null;
  }, [appLifecycleState]);

  // 长时间播放中途崩溃 / 被系统杀掉时的兜底: 播放中每 30s 检查一次,
  // 只有位置前进超过 20s 才真正写盘 (历史是整份 JSON 加密写, 别写太勤)。
  final lastAutoSavePosition = useRef<Duration?>(null);
  useEffect(() {
    final timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!context.mounted) return;
      try {
        final player = context.read<MediaPlayer>();
        if (!player.isPlaying || player.duration == Duration.zero) return;

        final last = lastAutoSavePosition.value;
        if (last != null &&
            (player.position - last).inMilliseconds.abs() < 20000) {
          return;
        }
        lastAutoSavePosition.value = player.position;
        unawaited(player.saveProgress());
      } catch (e) {
        logger('Auto save progress failed: $e');
      }
    });
    return timer.cancel;
  }, const []);
}
