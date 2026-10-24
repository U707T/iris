import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/player_gesture_layer.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';
import 'package:iris/pages/player/short_video/short_video_feed_widgets.dart';
import 'package:iris/pages/player/short_video/short_video_player.dart';
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
/// 手势不再自己实现: 横滑快进 / 双击快进 / 长按倍速全部交给
/// [PlayerGestureLayer]（与主窗口同一份代码、同一套阈值与提示），
/// 本文件只负责编排页面 (PageView)、队列同步与覆盖层组合。
///
/// - `short_video_wheel.dart`         鼠标滚轮切换上 / 下一条
/// - `short_video_volume.dart`        设备音量调节 (含音量按钮 / 指示器)
/// - `short_video_feed_widgets.dart`  画面 / 底部信息 / 进度条 / 操作按钮
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

    void commitPage(int page) {
      if (page < 0 || page >= items.length) return;
      final target = items[page].index;
      if (target != usePlayQueueStore().state.currentIndex) {
        usePlayQueueStore().updateCurrentIndex(target);
      }
    }

    // 长按加速播放（倍速的恢复逻辑与主窗口一致）
    final rateBeforeLongPress = useRef<double?>(null);
    final isLongPress = useState(false);

    void onLongPressStart() {
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
        if (restoreRate == null) return;
        rateBeforeLongPress.value = null;
        useAppStore().updateRate(restoreRate, persist: false);
      };
    }, const []);

    // 底部进度条拖动会话：与画面横滑共用同一套规则（暂停 / 预览 / 节流 / 续播），
    // 预览值也写进同一个 seekHub，所以时间与进度条跟手一致。
    final scrub = useMemoized(
      () => SeekSession(
        readPlayer: () => context.read<MediaPlayer>(),
        preview: seekHub.preview,
      ),
      [],
    );
    useEffect(() {
      return scrub.dispose;
    }, [scrub]);

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
        },
        onPointerUp: (_) => isDragging.value = false,
        onPointerCancel: (_) => isDragging.value = false,
        // 覆盖层 (底部信息 / 按钮) 挡住页面级滚轮时, 由此处兜底
        onPointerSignal: wheel.register,
        child: PlayerGestureLayer(
          readPlayer: () => context.read<MediaPlayer>(),
          seekStepSeconds: () => useAppStore().state.seekStepSeconds,
          // 纵向留给 PageView 翻页；横滑 = 进度（与主窗口同一套阈值）
          allowVertical: false,
          onTap: () => toggleShortVideoPlay(context),
          // 双击中间 1/3 = 播放暂停（与主窗口一致）
          onDoubleTapMiddle: () => toggleShortVideoPlay(context),
          onLongPressStart: onLongPressStart,
          onLongPressEnd: onLongPressEnd,
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
              // 底部信息与进度条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ShortVideoFeedFooter(
                  items: items,
                  currentFeedIndex: currentFeedIndex,
                  scrubPreview: seekHub.preview,
                  progressBar: ShortVideoFeedProgressBar(
                    scrubPreview: seekHub.preview,
                    onScrubStart: (target) {
                      // 进度条是「绝对定位」拖动：基准 = 按下处指向的目标，
                      // 起点取实时播放位置，再立即跳到按下点。
                      scrub.start(context.read<MediaPlayer>().position);
                      scrub.seekTo(target);
                    },
                    onScrubSeek: scrub.seekTo,
                    onScrubEnd: scrub.end,
                    // 点进度条跳转也走同一套会话（暂停 -> 落定 -> 续播），
                    // 与主窗口 Slider 的点击行为一致；旧实现是直接 seek，
                    // 播放中会「跳一下继续播」，两个模式手感不同。
                    onTapSeek: (target) {
                      scrub.start(context.read<MediaPlayer>().position);
                      scrub.seekTo(target);
                      scrub.end();
                    },
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
