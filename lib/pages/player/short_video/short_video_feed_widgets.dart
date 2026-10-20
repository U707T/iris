import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_volume.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/take_screenshot.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

/// 播放 / 暂停。
/// 播放器可能正在销毁 (例如刚好退出模式), 失败时忽略。
void toggleShortVideoPlay(BuildContext context) {
  final player = context.read<MediaPlayer>();
  if (player.isPlaying) {
    player.pause().catchError((_) {});
  } else {
    player.play().catchError((_) {});
  }
}

/// 当前页视频画面 (无预载池时的回退路径)
class ShortVideoFeedVideo extends StatelessWidget {
  const ShortVideoFeedVideo({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<MediaPlayer>();
    return SizedBox.expand(
      child: switch (player) {
        MediaKitPlayer player =>
          ShortVideoMediaKitSurface(controller: player.controller),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// Media Kit 视频画面 (始终 contain 适配)
class ShortVideoMediaKitSurface extends StatelessWidget {
  const ShortVideoMediaKitSurface({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        // 短视频流不显示字幕 (字幕功能已移除, 这里同时关掉字幕层)
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
        fit: BoxFit.contain,
      ),
    );
  }
}

/// 右侧操作按钮列
class ShortVideoFeedActions extends HookWidget {
  const ShortVideoFeedActions({super.key, required this.volume});

  final ShortVideoDeviceVolumeController volume;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 音量按钮放在暂停按钮上方 (右下区域里更靠上的位置)
        ShortVideoVolumeButton(volume: volume),
        const SizedBox(height: 12),
        ShortVideoFeedIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: t.play_pause,
          onPressed: () => toggleShortVideoPlay(context),
        ),
        const SizedBox(height: 12),
        ShortVideoFeedIconButton(
          icon: Icons.photo_camera_rounded,
          tooltip: t.screenshot,
          onPressed: () => takeScreenshot(context, context.read<MediaPlayer>()),
        ),
      ],
    );
  }
}

/// 底部标题 / 序号 / 时间与可拖拽进度条。
/// 渐变背景覆盖整个底部区域 (含进度条), 与视频明暗衔接自然。
class ShortVideoFeedFooter extends HookWidget {
  const ShortVideoFeedFooter({
    super.key,
    required this.items,
    required this.currentFeedIndex,
    required this.scrubPreview,
    required this.progressBar,
  });

  final List<PlayQueueItem> items;
  final int currentFeedIndex;
  final ValueNotifier<Duration?> scrubPreview;
  final Widget progressBar;

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<MediaPlayer, Duration>((player) => player.position);
    final duration =
        context.select<MediaPlayer, Duration>((player) => player.duration);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[currentFeedIndex].file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<Duration?>(
                    valueListenable: scrubPreview,
                    builder: (context, preview, _) {
                      final display = preview ?? position;
                      final TextStyle metaStyle = TextStyle(
                        color: Colors.white
                            .withValues(alpha: preview != null ? 1.0 : 0.7),
                        fontSize: 12,
                        decoration: TextDecoration.none,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 2),
                        ],
                      );
                      return Row(
                        children: [
                          Text(
                            '${currentFeedIndex + 1}/${items.length}',
                            style: metaStyle,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${formatDurationToMinutes(display)} / ${formatDurationToMinutes(duration)}',
                            style: metaStyle,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          progressBar,
        ],
      ),
    );
  }
}

/// 可拖拽 / 点击跳转的细进度条。
/// 拖动期间圆点与时间气泡由本地预览位置实时驱动, 不等待播放器回调。
class ShortVideoFeedProgressBar extends HookWidget {
  const ShortVideoFeedProgressBar({
    super.key,
    required this.scrubPreview,
    required this.onScrubStart,
    required this.onScrubSeek,
    required this.onScrubEnd,
    required this.onTapSeek,
  });

  final ValueNotifier<Duration?> scrubPreview;
  final void Function(Duration target) onScrubStart;
  final void Function(Duration target) onScrubSeek;
  final void Function() onScrubEnd;
  final void Function(Duration target) onTapSeek;

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<MediaPlayer, Duration>((player) => player.position);
    final duration =
        context.select<MediaPlayer, Duration>((player) => player.duration);

    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          Duration? targetOf(double localX) {
            if (duration <= Duration.zero) return null;
            final fraction = (localX / width).clamp(0.0, 1.0);
            return duration * fraction;
          }

          return ValueListenableBuilder<Duration?>(
            valueListenable: scrubPreview,
            builder: (context, preview, _) {
              final display = preview ?? position;
              final isSeeking = preview != null;
              final double progress = duration > Duration.zero
                  ? (display.inMilliseconds / duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                      .toDouble()
                  : 0.0;
              const double barHeight = 3.0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 拖动 / 点击热区 (translucent: 竖直滑动手势仍可穿透给翻页)
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (details) {
                      final target = targetOf(details.localPosition.dx);
                      if (target != null) onTapSeek(target);
                    },
                    onHorizontalDragStart: (details) {
                      final target = targetOf(details.localPosition.dx);
                      if (target != null) onScrubStart(target);
                    },
                    onHorizontalDragUpdate: (details) {
                      final target = targetOf(details.localPosition.dx);
                      if (target != null) onScrubSeek(target);
                    },
                    onHorizontalDragEnd: (_) => onScrubEnd(),
                    onHorizontalDragCancel: onScrubEnd,
                    child: const SizedBox.expand(),
                  ),
                  // 轨道
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    height: barHeight,
                    child: const IgnorePointer(
                      child: ColoredBox(color: Colors.white24),
                    ),
                  ),
                  // 已播放部分
                  Positioned(
                    left: 0,
                    bottom: 10,
                    height: barHeight,
                    width: width * progress,
                    child: const IgnorePointer(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
                  // 拖动圆点
                  Positioned(
                    left: (width * progress - 5).clamp(0.0, width - 10),
                    bottom: 10 + barHeight / 2 - 5,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: isSeeking ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black38, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 拖动进度预览
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: isSeeking ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${formatDurationToMinutes(display)} / ${formatDurationToMinutes(duration)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 圆形半透明底的操作按钮
class ShortVideoFeedIconButton extends StatelessWidget {
  const ShortVideoFeedIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 22),
        onPressed: onPressed,
      ),
    );
  }
}
