import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 播放失败提示。
///
/// 以前打不开的文件（权限失效的 content://、断网、编码不支持……）只会留下
/// 一块黑屏，用户不知道发生了什么，也没法重试。这里在装载失败时显示原因，
/// 并提供「重试」和「下一个」（队列里还有别的条目时）。
class PlaybackErrorOverlay extends HookWidget {
  const PlaybackErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final error =
        context.select<MediaPlayer, String?>((player) => player.error);
    final canRetry =
        context.select<MediaPlayer, bool>((player) => player.retry != null);
    final queueLength = usePlayQueueStore()
        .select(context, (state) => state.playQueue.length);

    if (error == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.unable_to_play,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (canRetry)
                        FilledButton.icon(
                          onPressed: () async {
                            // 用 read 取最新实例: 不要 select 函数本身,
                            // 否则每次进度更新 (新闭包) 都会让本组件重建
                            await context.read<MediaPlayer>().retry?.call();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(t.retry),
                        ),
                      if (queueLength > 1)
                        OutlinedButton.icon(
                          onPressed: () => usePlayQueueStore().next(),
                          icon: const Icon(Icons.skip_next_rounded),
                          label: Text(t.next),
                        ),
                    ],
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
