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

/// 播放器底部控制栏。
///
/// 两行 (手机 / 平板 / 窄桌面): 第一行只有播放控制 —— 随机 · 上一个 ·
/// 播放暂停 · 下一个 · 循环; 第二行只有四个入口 —— 画面适配 · 音量 ·
/// 播放队列 · 更多。
///
/// 单行 (桌面 ≥1200): 播放控制 + 画面适配 / 倍速 / 音量 + 进度条 + 队列 /
/// 全屏 / 更多。
///
/// 刷新播放列表、横竖屏、短视频、音轨、存储、倍速都不再占控制栏的位置:
/// 它们全在「更多」里 (窄屏是底部 sheet, 宽屏是 popup)。控制栏只保留
/// 每次播放都会用到的动作。
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
    // hook / store 订阅必须在 build 里调用 —— LayoutBuilder 的 builder 不是
    // hook 上下文 (`Hooks can only be called from the build method`), 所以先取
    // 状态, 再把"用哪个宽度排"交给 LayoutBuilder。
    final playQueue = usePlayQueueStore().select(
      context,
      (state) => state.playQueue,
    );
    final currentIndex = usePlayQueueStore().select(
      context,
      (state) => state.currentIndex,
    );

    final FileItem? file = useMemoized(() {
      final index = playQueue.indexWhere(
        (element) => element.index == currentIndex,
      );
      return playQueue.isEmpty || index < 0 ? null : playQueue[index].file;
    }, [playQueue, currentIndex]);

    final bool hasVideos = useMemoized(
      () => playQueue.any((e) => e.file.type == ContentType.video),
      [playQueue],
    );

    // 宽度必须读**自身约束**, 不能读 MediaQuery:
    // 系统小窗 / 分屏 / 侧边栏里, 控制栏拿到的盒子可能比窗口窄,
    // 按窗口宽度排按钮就会直接溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return _buildBar(context, width, file: file, hasVideos: hasVideos);
      },
    );
  }

  Widget _buildBar(
    BuildContext context,
    double width, {
    required FileItem? file,
    required bool hasVideos,
  }) {
    void enterShortVideo() {
      enterShortVideoMode();
    }

    final playPauseButton = PlayPauseButton(
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
    final playQueueButton = PlayQueueButton(
      showControlForHover: showControlForHover,
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

    final sliderWidget = ControlBarSlider(
      showControl: showControl,
      color: color,
    );

    final List<Widget> mobileTransportButtons = [
      shuffleButton,
      prevButton,
      playPauseButton,
      nextButton,
      repeatButton,
    ];
    final List<Widget> desktopTransportButtons = [
      playPauseButton,
      prevButton,
      nextButton,
      shuffleButton,
      repeatButton,
    ];

    // 两行布局的第二行: 四个入口, 不再随宽度增删。
    final List<Widget> toolButtons = [
      if (file?.type != ContentType.audio) fitButton,
      volumeWidget,
      playQueueButton,
      moreMenuButton,
    ];

    // 单行 (桌面) 布局: 传输按钮 + 视图组 + 进度条 + 面板组
    final List<Widget> viewButtons = [
      if (file?.type != ContentType.audio) fitButton,
      rateButton,
      volumeWidget,
    ];
    final List<Widget> panelButtons = [
      playQueueButton,
      if (isDesktop) fullscreenButton,
      moreMenuButton,
    ];

    const double desktopBreakpoint = 1200.0;

    final Widget controlLayout;
    if (width < desktopBreakpoint) {
      controlLayout = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sliderWidget,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: mobileTransportButtons,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: toolButtons,
          ),
        ],
      );
    } else {
      controlLayout = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...desktopTransportButtons,
          ...viewButtons,
          Expanded(child: sliderWidget),
          ...panelButtons,
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
