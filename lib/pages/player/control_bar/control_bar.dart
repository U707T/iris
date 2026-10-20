import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/player/control_bar/control_bar_buttons.dart';
import 'package:iris/pages/player/control_bar/control_bar_more_menu.dart';
import 'package:iris/pages/player/control_bar/control_bar_slider.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/short_video.dart';

/// 播放器底部控制栏: 按窗口宽度组合传输 / 视图 / 面板按钮 (移动 / 平板 / 桌面三档)。
///
/// 本文件只负责布局编排; 单个按钮的实现见 `control_bar_buttons.dart`,
/// 「更多」菜单见 `control_bar_more_menu.dart`。
class ControlBar extends HookWidget {
  const ControlBar({
    super.key,
    required this.showControl,
    required this.showControlForHover,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final Future<void> Function(Future<void> callback) showControlForHover;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    final playQueue =
        usePlayQueueStore().select(context, (state) => state.playQueue);
    final currentIndex =
        usePlayQueueStore().select(context, (state) => state.currentIndex);

    final FileItem? file = useMemoized(() {
      final index =
          playQueue.indexWhere((element) => element.index == currentIndex);
      return playQueue.isEmpty || index < 0 ? null : playQueue[index].file;
    }, [playQueue, currentIndex]);

    final bool hasVideos = useMemoized(
        () => playQueue.any((e) => e.file.type == ContentType.video),
        [playQueue]);

    void enterShortVideo() {
      enterShortVideoMode();
      // 进入模式后由预载池接管播放: enterShortVideoMode 已先静音旧播放器
      // (随后它会被异步销毁), 这里不要再把它拉起来, 否则与静音交接互相打架
      // (操作过快时的双声窗口)。
    }

    final playPauseButton = PlayPauseButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final stopButton = StopButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final prevButton = PreviousButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final nextButton = NextButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final shuffleButton = ShuffleButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final repeatButton = RepeatButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final fitButton = FitButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final zoomButton = ZoomButton(
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
    );
    final rateButton = RateButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final volumeWidget = VolumeWidget(
      width: width,
      showControl: showControl,
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
    );
    final audioTrackButton = AudioTrackButton(
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
    );
    final playQueueButton = PlayQueueButton(
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
    );
    final storageButton = StorageButton(
      showControlForHover: showControlForHover,
      color: color,
      overlayColor: overlayColor,
    );
    final shortVideoButton = ShortVideoButton(
      onPressed: enterShortVideo,
      color: color,
      overlayColor: overlayColor,
    );
    final fullscreenButton = FullscreenButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final moreMenuButton = MoreMenuButton(
      file: file,
      width: width,
      hasVideos: hasVideos,
      showControl: showControl,
      showControlForHover: showControlForHover,
      onEnterShortVideo: enterShortVideo,
      color: color,
      overlayColor: overlayColor,
    );

    final sliderWidget =
        ControlBarSlider(showControl: showControl, color: color);

    const double mobileBreakpoint = 640.0;
    const double tabletBreakpoint = 1024.0;

    final Widget controlLayout;

    if (width < mobileBreakpoint) {
      controlLayout = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sliderWidget,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              shuffleButton,
              prevButton,
              playPauseButton,
              stopButton,
              nextButton,
              repeatButton,
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (file?.type != ContentType.audio) fitButton,
              if (file?.type != ContentType.audio) zoomButton,
              volumeWidget,
              audioTrackButton,
              playQueueButton,
              storageButton,
              if (hasVideos) shortVideoButton,
              if (isDesktop) fullscreenButton,
              moreMenuButton,
            ],
          )
        ],
      );
    } else if (width < tabletBreakpoint) {
      controlLayout = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sliderWidget,
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              playPauseButton,
              stopButton,
              prevButton,
              nextButton,
              shuffleButton,
              repeatButton,
              if (file?.type != ContentType.audio) fitButton,
              if (file?.type != ContentType.audio) zoomButton,
              rateButton,
              volumeWidget,
              const Spacer(),
              audioTrackButton,
              playQueueButton,
              storageButton,
              if (hasVideos) shortVideoButton,
              if (isDesktop) fullscreenButton,
              moreMenuButton,
            ],
          ),
        ],
      );
    } else {
      controlLayout = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          playPauseButton,
          stopButton,
          prevButton,
          nextButton,
          shuffleButton,
          repeatButton,
          if (file?.type != ContentType.audio) fitButton,
          if (file?.type != ContentType.audio) zoomButton,
          rateButton,
          volumeWidget,
          Expanded(child: sliderWidget),
          audioTrackButton,
          playQueueButton,
          storageButton,
          if (hasVideos) shortVideoButton,
          if (isDesktop) fullscreenButton,
          moreMenuButton,
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.25),
            Colors.black.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: controlLayout,
    );
  }
}
