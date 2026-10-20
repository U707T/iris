import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/get_localizations.dart';

/// 播放失败提示 (装载超时 / 解码失败 / 网络错误)。
///
/// 只占中间一张卡片: 不铺满全屏, 否则会把下面的手势层与控制栏点击吃掉。
class PlaybackErrorOverlay extends StatelessWidget {
  const PlaybackErrorOverlay({
    super.key,
    required this.onRetry,
    this.fileName,
  });

  final VoidCallback onRetry;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return Center(
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                t.playback_failed,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              if (fileName != null && fileName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    fileName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
              TextButton(
                onPressed: onRetry,
                child: Text(t.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
