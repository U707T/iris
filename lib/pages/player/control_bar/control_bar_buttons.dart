import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/globals.dart' show rateMenuKey, speedStops;
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/pages/player/control_bar/volume_control.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/toggle_shuffle.dart';
import 'package:iris/widgets/dialogs/show_zoom_dialog.dart';
import 'package:iris/widgets/popup.dart';
import 'package:iris/widgets/popups/play_queue.dart';
import 'package:iris/widgets/popups/storages/storages.dart';
import 'package:iris/widgets/popups/track/subtitle_and_audio_track.dart';
import 'package:provider/provider.dart';

/// 播放 / 暂停按钮 (含初始化指示与拖动保护)
class PlayPauseButton extends HookWidget {
  const PlayPauseButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);
    final isInitializing =
        context.select<MediaPlayer, bool>((player) => player.isInitializing);
    final isSeeking =
        usePlayerUiStore().select(context, (state) => state.isSeeking);

    // 拖动进度条期间不跟随播放状态闪烁图标
    final displayIsPlaying = useState(isPlaying);
    useEffect(() {
      if (!isSeeking) {
        displayIsPlaying.value = isPlaying;
      }
      return null;
    }, [isPlaying]);

    return Stack(
      alignment: Alignment.center,
      children: [
        if (isInitializing)
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              color: Theme.of(context).colorScheme.surface,
            ),
          ),
        IconButton(
          tooltip: '${displayIsPlaying.value ? t.pause : t.play} ( Space )',
          icon: Icon(
            displayIsPlaying.value
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 32,
            color: color,
          ),
          onPressed: () {
            showControl();
            if (isPlaying) {
              useAppStore().updateAutoPlay(false);
              context.read<MediaPlayer>().pause();
            } else {
              useAppStore().updateAutoPlay(true);
              context.read<MediaPlayer>().play();
            }
          },
          style: ButtonStyle(overlayColor: overlayColor),
        ),
      ],
    );
  }
}

/// 停止: 暂停并清空当前播放项
class StopButton extends HookWidget {
  const StopButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return IconButton(
      tooltip: '${t.stop} ( Ctrl + C )',
      icon: Icon(
        Icons.stop_rounded,
        size: 26,
        color: color,
      ),
      onPressed: () {
        showControl();
        useAppStore().updateAutoPlay(false);
        context.read<MediaPlayer>().pause();
        usePlayQueueStore().updateCurrentIndex(-1);
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 上一条 (队列长度 > 1 时显示)
class PreviousButton extends HookWidget {
  const PreviousButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final int playQueueLength =
        usePlayQueueStore().select(context, (state) => state.playQueue.length);

    if (playQueueLength <= 1) return const SizedBox.shrink();

    return IconButton(
      tooltip: '${t.previous} ( Ctrl + ← )',
      icon: Icon(
        Icons.skip_previous_rounded,
        size: 26,
        color: color,
      ),
      onPressed: () {
        showControl();
        usePlayQueueStore().previous();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 下一条 (队列长度 > 1 时显示)
class NextButton extends HookWidget {
  const NextButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final int playQueueLength =
        usePlayQueueStore().select(context, (state) => state.playQueue.length);

    if (playQueueLength <= 1) return const SizedBox.shrink();

    return IconButton(
      tooltip: '${t.next} ( Ctrl + → )',
      icon: Icon(
        Icons.skip_next_rounded,
        size: 26,
        color: color,
      ),
      onPressed: () {
        showControl();
        usePlayQueueStore().next();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 随机开关
class ShuffleButton extends HookWidget {
  const ShuffleButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bool shuffle = useAppStore().select(context, (state) => state.shuffle);

    return IconButton(
      tooltip: '${t.shuffle}: ${shuffle ? t.on : t.off} ( Ctrl + X )',
      icon: Icon(
        Icons.shuffle_rounded,
        size: 20,
        color: !shuffle ? color?.withAlpha(153) : color,
      ),
      onPressed: () {
        showControl();
        toggleShuffle();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 循环模式切换
class RepeatButton extends HookWidget {
  const RepeatButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final Repeat repeat = useAppStore().select(context, (state) => state.repeat);

    return IconButton(
      tooltip:
          '${repeat == Repeat.one ? t.repeat_one : repeat == Repeat.all ? t.repeat_all : t.repeat_none} ( Ctrl + R )',
      icon: Icon(
        repeat == Repeat.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 20,
        color: repeat == Repeat.none ? color?.withAlpha(153) : color,
      ),
      onPressed: () {
        showControl();
        useAppStore().toggleRepeat();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 画面适配模式切换 (拉伸 / 裁剪 / 原始比例)
class FitButton extends HookWidget {
  const FitButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final BoxFit fit = useAppStore().select(context, (state) => state.fit);

    return IconButton(
      tooltip:
          '${t.video_zoom}: ${fit == BoxFit.contain ? t.fit : fit == BoxFit.fill ? t.stretch : fit == BoxFit.cover ? t.crop : '100%'} ( Ctrl + V )',
      icon: Icon(
        fit == BoxFit.contain
            ? Icons.fit_screen_rounded
            : fit == BoxFit.fill
                ? Icons.aspect_ratio_rounded
                : fit == BoxFit.cover
                    ? Icons.crop_landscape_rounded
                    : Icons.crop_free_rounded,
        size: 20,
        color: color,
      ),
      onPressed: () {
        showControl();
        useAppStore().toggleFit();
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 无级缩放 (打开缩放面板)
class ZoomButton extends HookWidget {
  const ZoomButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final zoom = usePlayerUiStore().select(context, (state) => state.zoom);

    return IconButton(
      tooltip: '${t.zoom}: ${(zoom * 100).round()}% ( Ctrl + 滚轮 )',
      icon: Icon(
        Icons.zoom_in_rounded,
        size: 20,
        color: zoom == 1.0 ? color?.withAlpha(153) : color,
      ),
      onPressed: () => showControlForHover(showZoomDialog(context)),
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 倍速菜单
class RateButton extends HookWidget {
  const RateButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final rate = useAppStore().select(context, (state) => state.rate);

    return PopupMenuButton(
      key: rateMenuKey,
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints(minWidth: 0),
      itemBuilder: (BuildContext context) => speedStops
          .map(
            (item) => PopupMenuItem(
              child: Text(
                '${item}X',
                style: TextStyle(
                  color: item == rate
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: item == rate ? FontWeight.bold : FontWeight.w100,
                  height: 1,
                ),
              ),
              onTap: () async {
                showControl();
                useAppStore().updateRate(item);
              },
            ),
          )
          .toList(),
      child: Tooltip(
        message: t.playback_speed,
        child: TextButton(
          onPressed: () => rateMenuKey.currentState?.showButtonMenu(),
          style: ButtonStyle(overlayColor: overlayColor),
          child: Text(
            '${rate}X',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 音量: 窄窗口为弹出面板, 宽窗口为内联滑条
class VolumeWidget extends HookWidget {
  const VolumeWidget({
    super.key,
    required this.width,
    required this.showControl,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final double width;
  final void Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final volume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);

    return width < 768
        ? Builder(
            builder: (context) => IconButton(
              tooltip: '${t.volume}: $volume',
              icon: Icon(
                isMuted || volume == 0
                    ? Icons.volume_off_rounded
                    : volume < 50
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                size: 20,
                color: color,
              ),
              onPressed: () => showControlForHover(
                showVolumePopover(context, showControl),
              ),
              style: ButtonStyle(overlayColor: overlayColor),
            ),
          )
        : SizedBox(
            width: 160,
            child: VolumeControl(
              showControl: showControl,
              showVolumeText: false,
              color: color,
              overlayColor: overlayColor,
            ),
          );
  }
}

/// 字幕与音轨
class SubtitleButton extends HookWidget {
  const SubtitleButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return IconButton(
      tooltip: '${t.subtitle_and_audio_track} ( S )',
      icon: Icon(
        Icons.subtitles_rounded,
        size: 20,
        color: color,
      ),
      onPressed: () async {
        showControlForHover(
          showPopup(
            context: context,
            child: Provider<MediaPlayer>.value(
              value: context.read<MediaPlayer>(),
              child: const SubtitleAndAudioTrack(),
            ),
            direction: PopupDirection.right,
          ),
        );
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 播放队列
class PlayQueueButton extends HookWidget {
  const PlayQueueButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return IconButton(
      tooltip: '${t.play_queue} ( P )',
      icon: Transform.translate(
        offset: const Offset(1, 1.5),
        child: Icon(
          Icons.playlist_play_rounded,
          size: 28,
          color: color,
        ),
      ),
      onPressed: () async {
        showControlForHover(
          showPopup(
            context: context,
            child: const PlayQueue(),
            direction: PopupDirection.right,
          ),
        );
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 存储 (打开文件)
class StorageButton extends HookWidget {
  const StorageButton({
    super.key,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return IconButton(
      tooltip: '${t.storage} ( F )',
      icon: Icon(
        Icons.storage_rounded,
        size: 18,
        color: color,
      ),
      onPressed: () => showControlForHover(
        showPopup(
          context: context,
          child: const Storages(),
          direction: PopupDirection.right,
        ),
      ),
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 进入短视频模式
class ShortVideoButton extends HookWidget {
  const ShortVideoButton({
    super.key,
    required this.onPressed,
    this.color,
    this.overlayColor,
  });

  final VoidCallback onPressed;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return IconButton(
      tooltip: t.short_video_mode,
      icon: Icon(
        Icons.swipe_vertical_rounded,
        size: 20,
        color: color,
      ),
      onPressed: onPressed,
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}

/// 全屏切换
class FullscreenButton extends HookWidget {
  const FullscreenButton({
    super.key,
    required this.showControl,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isFullScreen =
        usePlayerUiStore().select(context, (state) => state.isFullScreen);

    return IconButton(
      tooltip: isFullScreen
          ? '${t.exit_fullscreen} ( Escape, F11, Enter )'
          : '${t.enter_fullscreen} ( F11, Enter )',
      icon: Icon(
        isFullScreen
            ? Icons.close_fullscreen_rounded
            : Icons.open_in_full_rounded,
        size: 19,
        color: color,
      ),
      onPressed: () async {
        showControl();
        usePlayerUiStore().updateFullScreen(!isFullScreen);
      },
      style: ButtonStyle(overlayColor: overlayColor),
    );
  }
}
