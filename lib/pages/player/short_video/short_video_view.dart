import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_feed_widgets.dart';
import 'package:iris/pages/player/short_video/short_video_player.dart';
import 'package:iris/pages/player/short_video/short_video_scrub.dart';
import 'package:iris/pages/player/short_video/short_video_seek_feedback.dart';
import 'package:iris/pages/player/short_video/short_video_volume.dart';
import 'package:iris/pages/player/short_video/short_video_wheel.dart';
import 'package:iris/pages/player/overlays/playback_error_overlay.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/short_video.dart';
import 'package:iris/widgets/speed_boost_effect.dart';
import 'package:provider/provider.dart';

/// 短视频模式 (类抖音的竖向信息流界面):
/// 一屏一条视频, 上滑下一条 / 下滑上一条, 单条循环播放。
/// Media Kit 后端配合预载播放器池, 滑动切换无缝衔接。
///
/// 本文件只负责编排: 页面 (PageView) 与队列同步、手势接线、覆盖层组合。
/// 各交互系统的状态与规则在各自文件里:
/// - `short_video_wheel.dart`         鼠标滚轮切换上 / 下一条
/// - `short_video_scrub.dart`         进度拖动会话 (画面拖动 / 进度条共用)
/// - `short_video_volume.dart`        设备音量调节 (含音量按钮 / 指示器)
/// - `short_video_feed_widgets.dart`  画面 / 底部信息 / 进度条 / 操作按钮
/// - `short_video_seek_feedback.dart` 双击快进 / 快退提示
class ShortVideoView extends HookWidget {
  const ShortVideoView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final player = context.read<MediaPlayer>();
    final pool = player is ShortVideoMediaKitPlayer ? player.pool : null;
    // 池内画面就绪时刷新预载页面
    useListenable(pool);

    final playQueue =
        usePlayQueueStore().select(context, (state) => state.playQueue);
    final currentIndex =
        usePlayQueueStore().select(context, (state) => state.currentIndex);

    // 短视频流 = 播放队列中的视频条目 (跳过音频)
    final items = useMemoized(() => getVideoItems(playQueue), [playQueue]);
    final currentFeedIndex = useMemoized(
      () => items.indexWhere((item) => item.index == currentIndex),
      [items, currentIndex],
    );

    final int safeIndex = currentFeedIndex < 0 ? 0 : currentFeedIndex;
    final pageController =
        useMemoized(() => PageController(initialPage: safeIndex), []);
    useEffect(() {
      return () => pageController.dispose();
    }, [pageController]);

    // 队列为空 / 当前项不是视频时 (如打开了音频), 自动退出短视频模式
    final exitRequested = useRef(false);
    useEffect(() {
      if (items.isEmpty || currentFeedIndex < 0) {
        if (!exitRequested.value) {
          exitRequested.value = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => exitShortVideoMode());
        }
      }
      return;
    }, [items, currentFeedIndex]);

    final isInitializing =
        context.select<MediaPlayer, bool>((player) => player.isInitializing);
    final playbackError =
        context.select<MediaPlayer, String?>((player) => player.error);

    // 程序化翻页期间忽略 onPageChanged: 跨多页时会依次回调每个中间页,
    // 每次 commitPage 都会把 currentIndex 改到中间页, 形成来回打架。
    // 用递增 generation 而不是 bool: 连续快捷键会叠加多个动画, 前一个动画的
    // 完成回调不能把后一个动画的"同步中"状态提前清掉。
    final isSyncingPage = useRef(false);
    final pageSyncGeneration = useRef(0);

    // 队列索引被外部改变时 (快捷键切换等) 同步 PageView
    useEffect(() {
      if (!pageController.hasClients || currentFeedIndex < 0) return;
      final page = pageController.page?.round() ?? pageController.initialPage;
      if (page == currentFeedIndex) return;

      final generation = ++pageSyncGeneration.value;
      isSyncingPage.value = true;

      if (page < 0 || page >= items.length) {
        pageController.jumpToPage(currentFeedIndex);
        if (generation == pageSyncGeneration.value) {
          isSyncingPage.value = false;
        }
      } else {
        pageController
            .animateToPage(
              currentFeedIndex,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            )
            .then(
          (_) {
            if (generation == pageSyncGeneration.value) {
              isSyncingPage.value = false;
            }
          },
          onError: (Object error, StackTrace stack) {
            logger('Short video page sync failed: $error');
            if (generation == pageSyncGeneration.value) {
              isSyncingPage.value = false;
            }
          },
        );
      }
      return;
    }, [currentFeedIndex]);

    final isDragging = useRef(false);
    // 长按回调本身不带 pointer kind, 只能靠按下时记录; 触摸屏笔记本上
    // 上一次触摸的 kind 不能残留给下一次鼠标长按。
    final lastPointerKind = useRef<PointerDeviceKind?>(null);

    void commitPage(int page) {
      if (page < 0 || page >= items.length) return;
      final target = items[page].index;
      if (target != usePlayQueueStore().state.currentIndex) {
        usePlayQueueStore().updateCurrentIndex(target);
      }
    }

    // 双击快进 / 快退的瞬时提示 (方向 + 步长)
    final seekFeedback =
        useMemoized(() => ShortVideoSeekFeedbackController(), []);
    useEffect(() {
      return seekFeedback.dispose;
    }, [seekFeedback]);

    // 双击快进 / 快退。
    // 注意: 不能用 build 时捕获的 player —— 短视频模式播放期间本组件不会重建,
    // 捕获实例里的 position 是过期的 (≈0), 会导致快进总是从视频开头开始;
    // context.read 取到的是随播放进度持续刷新的当前实例。
    void onDoubleTapDown(TapDownDetails details) {
      final seekStep = useAppStore().state.seekStepSeconds;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final tapDx = details.globalPosition.dx;
      final currentPlayer = context.read<MediaPlayer>();

      if (tapDx > screenWidth * 0.75) {
        currentPlayer.forward(seekStep);
        seekFeedback.show(forward: true, seconds: seekStep);
      } else if (tapDx < screenWidth * 0.25) {
        currentPlayer.backward(seekStep);
        seekFeedback.show(forward: false, seconds: seekStep);
      } else {
        toggleShortVideoPlay(context);
      }
    }

    // 长按加速播放
    final rateBeforeLongPress = useRef<double?>(null);
    final isLongPress = useState(false);

    void onLongPressStart(LongPressStartDetails details) {
      if (lastPointerKind.value != PointerDeviceKind.touch) return;
      if (!context.read<MediaPlayer>().isPlaying) return;
      rateBeforeLongPress.value = useAppStore().state.rate;
      useAppStore().updateRate(
        useAppStore().state.longPressSpeed,
        persist: false,
      );
      isLongPress.value = true;
    }

    void onLongPressEnd() {
      final restoreRate = rateBeforeLongPress.value;
      if (restoreRate == null) return;
      useAppStore().updateRate(restoreRate, persist: false);
      rateBeforeLongPress.value = null;
      isLongPress.value = false;
    }

    // 退出模式 / 组件销毁时必须恢复倍速: onLongPressEnd 不保证一定到达,
    // 否则 rate 会永久停在 longPressSpeed, 下一条视频也受影响。
    useEffect(() {
      return () {
        final restoreRate = rateBeforeLongPress.value;
        if (restoreRate != null) {
          rateBeforeLongPress.value = null;
          useAppStore().updateRate(restoreRate, persist: false);
        }
      };
    }, const []);

    // 进度拖动会话 (画面横向拖动 / 底部进度条共用)
    final scrub = useMemoized(
      () => ShortVideoScrubSession(
        readPlayer: () => context.read<MediaPlayer>(),
      ),
      [],
    );
    useEffect(() {
      return scrub.dispose;
    }, [scrub]);

    // 水平拖动调节进度 (相对拖动, 任意位置可用)
    final scrubState =
        useRef((active: false, start: Duration.zero, startDx: 0.0));

    void onHorizontalDragStart(DragStartDetails details) {
      if (details.kind == PointerDeviceKind.touch) {
        // 左右边缘留给系统返回手势
        const double edgeDeadZone = 48.0;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final startDx = details.globalPosition.dx;
        if (startDx < edgeDeadZone || startDx > screenWidth - edgeDeadZone) {
          return;
        }
      }
      // 同 onDoubleTapDown: 取当前实例的实时位置, 避免从过期位置 (≈0) 开始拖动
      final currentPosition = context.read<MediaPlayer>().position;
      scrubState.value = (
        active: true,
        start: currentPosition,
        startDx: details.globalPosition.dx,
      );
      scrub.start(currentPosition);
    }

    void onHorizontalDragUpdate(DragUpdateDetails details) {
      if (!scrubState.value.active) return;
      final totalDx = details.globalPosition.dx - scrubState.value.startDx;
      const double sensitivity = 3.0; // 每滑动 3 像素代表 1 秒
      final target = scrubState.value.start +
          Duration(milliseconds: (totalDx / sensitivity * 1000).round());
      scrub.seek(target);
    }

    void onHorizontalDragEnd() {
      if (!scrubState.value.active) return;
      scrubState.value = (active: false, start: Duration.zero, startDx: 0.0);
      scrub.end();
    }

    // 设备音量调节 (音量按钮上按住上下滑动 / 悬停滚轮微调)
    final volume = useMemoized(() => ShortVideoDeviceVolumeController(), []);
    useEffect(() {
      return volume.dispose;
    }, [volume]);

    // 鼠标滚轮切换上 / 下一条 (接管 PageView 默认的滚轮行为;
    // 注册逻辑与增量规则见 ShortVideoWheelSwitcher)
    final wheel = useMemoized(
        () => ShortVideoWheelSwitcher(onSwitch: moveShortVideoBy), []);

    Widget buildPage(BuildContext context, int index) {
      // 预载池里有该下标的画面就直接使用 (滑动时可见下一帧)
      final slot = pool?.slotFor(index);
      final Widget content;
      if (slot != null) {
        // key 绑定到播放器实例: 槽位换播放器时强制重建画面 widget,
        // 避免复用旧的订阅 / 可见性状态
        content = ShortVideoMediaKitSurface(
          key: ValueKey(slot.controller),
          controller: slot.controller,
        );
      } else if (index == currentFeedIndex) {
        content = const ShortVideoFeedVideo();
      } else {
        content = const ColoredBox(color: Colors.black);
      }
      // 页面级滚轮注册: 先于 PageView 的 Scrollable 拿到事件
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: wheel.register,
        child: content,
      );
    }

    if (items.isEmpty || currentFeedIndex < 0) {
      return const SizedBox.shrink();
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Listener(
        onPointerDown: (event) {
          isDragging.value = true;
          lastPointerKind.value = event.kind;
        },
        onPointerUp: (_) => isDragging.value = false,
        onPointerCancel: (_) => isDragging.value = false,
        // 覆盖层 (底部信息 / 按钮) 挡住页面级滚轮时, 由此处兜底
        onPointerSignal: wheel.register,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => toggleShortVideoPlay(context),
          onDoubleTapDown: onDoubleTapDown,
          onLongPressStart: onLongPressStart,
          onLongPressEnd: (_) => onLongPressEnd(),
          onLongPressCancel: onLongPressEnd,
          onHorizontalDragStart: onHorizontalDragStart,
          onHorizontalDragUpdate: onHorizontalDragUpdate,
          onHorizontalDragEnd: (_) => onHorizontalDragEnd(),
          onHorizontalDragCancel: onHorizontalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // 吸附 / 回弹结束后提交页面切换
                  if (notification is ScrollEndNotification) {
                    final page = pageController.page?.round();
                    if (page != null) commitPage(page);
                  }
                  return false;
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                    overscroll: false,
                    dragDevices: const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: PageView.builder(
                    controller: pageController,
                    scrollDirection: Axis.vertical,
                    onPageChanged: (page) {
                      // 仅在非拖动 / 非程序化翻页阶段提交, 避免中途切换播放
                      if (!isDragging.value && !isSyncingPage.value) {
                        commitPage(page);
                      }
                    },
                    itemCount: items.length,
                    itemBuilder: buildPage,
                  ),
                ),
              ),
              // 加载指示
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isInitializing
                        ? const Center(
                            child: CircularProgressIndicator(
                              key: ValueKey('loading'),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('loaded')),
                  ),
                ),
              ),
              // 长按倍速动效 (与主播放界面共用)
              SpeedBoostEffect(visible: isLongPress.value),
              // 播放失败提示: 点重试 = 让当前槽位重新 open
              if (playbackError != null && currentFeedIndex >= 0)
                Positioned.fill(
                  child: PlaybackErrorOverlay(
                    fileName: items[currentFeedIndex].file.name,
                    onRetry: () => context.read<MediaPlayer>().play(),
                  ),
                ),
              // 双击快进 / 快退提示 (方向 + 步长)
              Positioned.fill(
                child: ShortVideoSeekFeedbackOverlay(controller: seekFeedback),
              ),
              // 底部信息与进度条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ShortVideoFeedFooter(
                  items: items,
                  currentFeedIndex: currentFeedIndex,
                  scrubPreview: scrub.preview,
                  progressBar: ShortVideoFeedProgressBar(
                    scrubPreview: scrub.preview,
                    onScrubStart: scrub.start,
                    onScrubSeek: scrub.seek,
                    onScrubEnd: scrub.end,
                    onTapSeek: (target) =>
                        context.read<MediaPlayer>().seek(target),
                  ),
                ),
              ),
              // 退出按钮 (让出刘海 / 状态栏安全区)
              Positioned(
                left: 8,
                top: 8 + MediaQuery.viewPaddingOf(context).top,
                child: ShortVideoFeedIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: t.exit_short_video_mode,
                  onPressed: exitShortVideoMode,
                ),
              ),
              // 右侧操作
              Positioned(
                right: 10,
                bottom: 110,
                child: ShortVideoFeedActions(volume: volume),
              ),
              // 音量调节指示 (长按音量按钮上下滑动时显示)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double?>(
                    valueListenable: volume.preview,
                    builder: (context, preview, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: preview == null
                          ? const SizedBox.shrink(
                              key: ValueKey('no-volume-hint'))
                          : Center(
                              key: const ValueKey('volume-hint'),
                              child: ShortVideoVolumeIndicator(volume: preview),
                            ),
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
