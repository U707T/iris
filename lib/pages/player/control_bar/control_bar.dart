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
/// 两行布局 (手机 / 平板 / 窄桌面): 第一行是播放控制 —— 随机 · 上一个 ·
/// 播放暂停 · 下一个 · 循环; 第二行是工具 —— 画面适配 · 音量 · 面板 ·
/// 短视频 · 刷新播放列表 · 横竖屏 · 更多。
///
/// 「停止」与「缩放」不再占位置: 停止 = 暂停 + 清空队列 (`Ctrl + C` 仍在),
/// 缩放走双指 / `Ctrl + 滚轮`, 精确面板收进「更多 → 缩放」。
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
    final refreshButton = RefreshPlayQueueButton(
      showControl: showControl,
      color: color,
      overlayColor: overlayColor,
    );
    final orientationButton = OrientationButton(
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
    // 512 以下 (手机 + 小尺寸分屏) 把音轨 / 存储收进「更多」菜单。
    // v2.6.6 之前这条线是 448 —— 那时第二行最多 8 个按钮, 448 正好卡得住;
    // 加进刷新 / 横竖屏之后最多 9 个 (48dp 点击区 × 9 = 432 + 16 内边距),
    // 只能上移, 否则 448–511 这一段会排成一条零间隔的图标带。
    const double compactBreakpoint = 512.0;
    const double desktopBreakpoint = 1200.0;
    final bool compact = width < compactBreakpoint;

    final moreMenuButton = MoreMenuButton(
      file: file,
      width: width,
      hasVideos: hasVideos,
      compact: compact,
      showControl: showControl,
      showControlForHover: showControlForHover,
      onEnterShortVideo: enterShortVideo,
      color: color,
      overlayColor: overlayColor,
    );

    final sliderWidget =
        ControlBarSlider(showControl: showControl, color: color);

    // 按钮只声明一次, 两种布局只决定"怎么摆":
    // 以前三份列表各写一遍, 已经分叉 (mobile 没有 rate), 加按钮要改三处。
    // 单行 (桌面) 把播放键放最左; 两行布局的第一行是对称的
    // 随机 | 上 | 播 | 下 | 循环。
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

    // 两行布局的第二行, 从左到右按"用得多 → 用得少"排:
    // 画面适配 → 倍速 → 音量 → (音轨 / 存储) → 播放队列 → 短视频
    // → 刷新 → 横竖屏 → 更多。
    // 「更多」永远压最右, 刷新 / 横竖屏紧挨着它 —— 这三个是"工具的工具",
    // 与左边一排和播放直接相关的按钮区分开。
    final List<Widget> toolButtons = [
      if (file?.type != ContentType.audio) fitButton,
      // 手机上这一行放不下, rate 只保留在宽屏
      if (width >= 640) rateButton,
      volumeWidget,
      if (!compact) audioTrackButton,
      if (!compact) storageButton,
      playQueueButton,
      if (hasVideos) shortVideoButton,
      refreshButton,
      // 桌面窗口没有"屏幕方向"这回事, 这个按钮只给手机 / 平板
      if (!isDesktop) orientationButton,
      moreMenuButton,
    ];

    // 单行 (桌面) 布局用的"视图组": 夹在传输按钮和进度条之间
    final List<Widget> viewButtons = [
      if (file?.type != ContentType.audio) fitButton,
      if (width >= 640) rateButton,
      volumeWidget,
    ];
    // 单行 (桌面) 布局用的"面板组": 全屏只有桌面有, 音轨 / 存储在窄窗口里
    // 已经收进「更多」菜单 (见上面的 compactBreakpoint)
    final List<Widget> panelButtons = [
      if (!compact) audioTrackButton,
      playQueueButton,
      if (!compact) storageButton,
      if (hasVideos) shortVideoButton,
      refreshButton,
      if (isDesktop && !compact) fullscreenButton,
      moreMenuButton,
    ];

    // 第二行窄屏会把 48dp 的点击留白收成 IconButton 自己的 40dp:
    // 360 逻辑宽下 7 个 48dp 按钮只剩 8px 余量, 图标几乎贴在一起。
    final bool denseToolRow = width < 420;
    final Widget toolRow = IconButtonTheme(
      data: IconButtonThemeData(
        style: denseToolRow
            ? const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: toolButtons,
      ),
    );

    final Widget controlLayout;
    if (width < desktopBreakpoint) {
      // 两行布局覆盖手机、平板和窄桌面窗口。
      // 原来的 640–1023 单行约需 480–768px 固定宽度, 在 640/768 窗口必炸。
      controlLayout = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sliderWidget,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: mobileTransportButtons,
          ),
          toolRow,
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
