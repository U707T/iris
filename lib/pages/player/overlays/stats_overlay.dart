import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/player.dart';
import 'package:provider/provider.dart';

/// 播放统计 OSD (帧率 / 丢帧 / 解码器 / 码率 等)
class StatsOverlay extends HookWidget {
  const StatsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MediaPlayer>();

    // 每秒刷新一次统计
    final tick = useState(0);
    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (context.mounted) tick.value++;
      });
      return timer.cancel;
    }, []);

    final stats = useMemoized(() => player.getStats?.call(), [tick.value]);

    final rows = <MapEntry<String, String>>[];

    // 分辨率与基础信息始终显示
    if (player.width > 0 && player.height > 0) {
      rows.add(MapEntry('分辨率',
          '${player.width.toInt()} x ${player.height.toInt()}'));
    }

    if (stats != null) {
      stats.forEach((key, value) {
        rows.add(MapEntry(key, value));
      });
    }

    if (player.duration.inMilliseconds > 0) {
      final secs = player.position.inSeconds;
      final total = player.duration.inSeconds;
      rows.add(MapEntry('播放', '$secs s / $total s'));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      top: 56,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...rows.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
