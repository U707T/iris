import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/utils/format_duration_to_minutes.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/short_video.dart';
import 'package:iris/utils/take_screenshot.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

void _togglePlay(BuildContext context) {
  final player = context.read<MediaPlayer>();
  // 播放器可能正在销毁 (例如刚好退出模式), 失败时忽略
  if (player.isPlaying) {
    player.pause().catchError((_) {});
  } else {
    player.play().catchError((_) {});
  }
}

/// 滚轮切换的累积阈值 (逻辑像素)。
/// Windows 一个标准滚轮刻度约 33~100px (取决于系统"每次滚动几行": 行数 × 100/3),
/// 高精度滚轮 / 远程桌面平滑滚动会把一个刻度拆成很多小增量;
/// 统一累积到阈值再切换, 避免细粒度设备上滚轮完全没有反应。
const double _wheelSwitchThreshold = 30.0;

/// 两次滚轮事件间隔超过该值视为新的滚动动作, 累积重新计数。
const Duration _wheelGestureGap = Duration(milliseconds: 400);

/// 两次切换之间的最小间隔 (避免快速滚动一次跳过太多视频)。
const Duration _wheelSwitchCooldown = Duration(milliseconds: 420);

/// 短视频模式 (类抖音的竖向信息流界面):
/// 一屏一条视频, 上滑下一条 / 下滑上一条, 单条循环播放。
/// Media Kit 后端配合预载播放器池, 滑动切换无缝衔接。
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

    // 队列索引被外部改变时 (快捷键切换等) 同步 PageView
    useEffect(() {
      if (!pageController.hasClients || currentFeedIndex < 0) return;
      final page = pageController.page?.round() ?? pageController.initialPage;
      if (page == currentFeedIndex) return;
      if (page < 0 || page >= items.length) {
        pageController.jumpToPage(currentFeedIndex);
      } else {
        pageController.animateToPage(
          currentFeedIndex,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
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
      } else if (tapDx < screenWidth * 0.25) {
        currentPlayer.backward(seekStep);
      } else {
        _togglePlay(context);
      }
    }

    // 长按加速播放
    final rateBeforeLongPress = useRef<double?>(null);
    final isLongPress = useState(false);

    void onLongPressStart(LongPressStartDetails details) {
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

    // 进度拖动: 本地预览位置让进度条实时跟手, 预览 seek 做节流,
    // 拖动时暂停播放, 松手后精确 seek 并恢复播放。
    final scrubPreview = useMemoized(() => ValueNotifier<Duration?>(null), []);
    final scrubAlive = useRef(true);
    useEffect(() {
      scrubAlive.value = true;
      return () {
        scrubAlive.value = false;
        scrubPreview.dispose();
      };
    }, [scrubPreview]);
    final scrubSession = useRef(0);
    final scrubActive = useRef(false);
    final scrubResume = useRef(false);
    final lastScrubSeekAt = useRef<DateTime?>(null);

    void scrubSeek(Duration target, {bool force = false}) {
      if (!force && !scrubActive.value) return;
      scrubPreview.value = target;
      final now = DateTime.now();
      final last = lastScrubSeekAt.value;
      if (force ||
          last == null ||
          now.difference(last) >= const Duration(milliseconds: 140)) {
        lastScrubSeekAt.value = now;
        player.seek(target);
      }
    }

    void scrubStart(Duration target) {
      scrubSession.value++;
      scrubActive.value = true;
      // 同 onDoubleTapDown: 用 context.read 取实时实例 —— 播放期间本组件不会重建,
      // build 时捕获的实例里 isPlaying 是过期的, 先暂停再拖动时会误判为"未播放",
      // 松手后不恢复 (或反过来意外恢复) 播放。
      final currentPlayer = context.read<MediaPlayer>();
      scrubResume.value = currentPlayer.isPlaying;
      if (scrubResume.value) currentPlayer.pause();
      lastScrubSeekAt.value = null;
      scrubSeek(target, force: true);
    }

    void scrubEnd() {
      if (!scrubActive.value) return;
      final target = scrubPreview.value;
      scrubActive.value = false;
      lastScrubSeekAt.value = null;
      final resume = scrubResume.value;
      scrubResume.value = false;
      final session = ++scrubSession.value;
      if (target != null) player.seek(target);
      if (resume) player.play();
      // 保持预览位置一小段时间, 避免松手瞬间进度先回跳再跳
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (scrubAlive.value && scrubSession.value == session) {
          scrubPreview.value = null;
        }
      });
    }

    // 音量调节 (长按音量按钮后上下滑动):
    // 与进度拖动同一套思路 —— 本地预览值实时跟手 (只重建指示器),
    // 写入 store 做节流 (避免每帧都触发 3 个播放器的 setVolume),
    // 松手时落盘一次。
    final volumePreview = useMemoized(() => ValueNotifier<double?>(null), []);
    final volumeAlive = useRef(true);
    useEffect(() {
      volumeAlive.value = true;
      return () {
        volumeAlive.value = false;
        volumePreview.dispose();
      };
    }, [volumePreview]);
    final volumeSession = useRef(0);
    final volumeActive = useRef(false);
    final volumeStart = useRef(0);
    final volumeStartDy = useRef(0.0);
    final lastVolumePushAt = useRef<DateTime?>(null);

    /// 每滑动该像素数代表 1% 音量 (上下滑 260px = 0~100)
    const double volumeDragPixelsPerPercent = 2.6;
    /// 写入 store 的最小间隔
    const Duration volumePushInterval = Duration(milliseconds: 100);

    void pushVolume(double value, {bool force = false}) {
      final now = DateTime.now();
      final last = lastVolumePushAt.value;
      if (force ||
          last == null ||
          now.difference(last) >= volumePushInterval) {
        lastVolumePushAt.value = now;
        unawaited(useAppStore().updateVolume(value.round(), persist: false));
      }
    }

    void volumeAdjustStart(Offset globalPosition) {
      volumeSession.value++;
      volumeActive.value = true;
      final appState = useAppStore().state;
      // 静音状态下调节音量 -> 自动取消静音, 否则调了也听不到
      if (appState.isMuted) {
        unawaited(useAppStore().updateMute(false));
      }
      volumeStart.value = appState.volume;
      volumeStartDy.value = globalPosition.dy;
      lastVolumePushAt.value = null;
      volumePreview.value = appState.volume.toDouble();
    }

    void volumeAdjustUpdate(Offset globalPosition) {
      if (!volumeActive.value) return;
      final delta =
          (volumeStartDy.value - globalPosition.dy) / volumeDragPixelsPerPercent;
      final value = (volumeStart.value + delta).clamp(0.0, 100.0);
      volumePreview.value = value;
      pushVolume(value);
    }

    void volumeAdjustEnd() {
      if (!volumeActive.value) return;
      volumeActive.value = false;
      lastVolumePushAt.value = null;
      final value = volumePreview.value;
      final session = ++volumeSession.value;
      // 落盘最终值
      if (value != null) {
        unawaited(useAppStore().updateVolume(value.round()));
      }
      // 保留预览值一小段时间, 避免松手瞬间指示器先跳回旧值
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (volumeAlive.value && volumeSession.value == session) {
          volumePreview.value = null;
        }
      });
    }

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
      scrubStart(currentPosition);
    }

    void onHorizontalDragUpdate(DragUpdateDetails details) {
      if (!scrubState.value.active) return;
      final totalDx = details.globalPosition.dx - scrubState.value.startDx;
      const double sensitivity = 3.0; // 每滑动 3 像素代表 1 秒
      final target = scrubState.value.start +
          Duration(milliseconds: (totalDx / sensitivity * 1000).round());
      scrubSeek(target);
    }

    void onHorizontalDragEnd() {
      if (!scrubState.value.active) return;
      scrubState.value = (active: false, start: Duration.zero, startDx: 0.0);
      scrubEnd();
    }

    // 鼠标滚轮切换上 / 下一条 (接管 PageView 默认的滚轮行为)。
    // 注册点在两处, 缺一不可:
    // - buildPage 内的页面级 Listener: 位于 PageView 内部, 会先于 Scrollable
    //   拿到事件, 屏蔽其默认的滚轮翻页;
    // - 根部 Listener: 底部信息栏 / 按钮等覆盖层会吸收命中测试,
    //   指针在这些区域滚动时只有根部 Listener 能收到事件。
    // 增量处理: 累积到阈值再切换 —— 标准滚轮一格约 33~100px, 单次事件即达
    // 阈值; 高精度滚轮 / 远程桌面的细粒度增量则逐次累积 (此前直接丢弃
    // <4px 的增量, 导致这类设备上滚轮完全没有反应)。
    final wheelCooldown = useRef<DateTime?>(null);
    final wheelAccumulator = useRef(0.0);
    final wheelLastEventAt = useRef<DateTime?>(null);

    void registerWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
        final scrollEvent = resolved as PointerScrollEvent;
        final dy = scrollEvent.scrollDelta.dy;
        if (dy == 0) return;
        final now = DateTime.now();

        // 冷却期内直接丢弃, 避免快速滚动一次跳过太多视频
        final lastSwitch = wheelCooldown.value;
        if (lastSwitch != null &&
            now.difference(lastSwitch) < _wheelSwitchCooldown) {
          wheelAccumulator.value = 0;
          return;
        }

        // 间隔过久视为新的滚动动作; 反向滚动也从当前增量重新开始累积
        final lastEventAt = wheelLastEventAt.value;
        if (lastEventAt == null ||
            now.difference(lastEventAt) > _wheelGestureGap) {
          wheelAccumulator.value = 0;
        }
        wheelLastEventAt.value = now;
        final accumulated = wheelAccumulator.value;
        wheelAccumulator.value =
            accumulated == 0 || accumulated.sign == dy.sign
                ? accumulated + dy
                : dy;

        if (wheelAccumulator.value.abs() < _wheelSwitchThreshold) return;
        final direction = wheelAccumulator.value > 0 ? 1 : -1;
        wheelAccumulator.value = 0;
        wheelCooldown.value = now;
        moveShortVideoBy(direction);
      });
    }

    Widget buildPage(BuildContext context, int index) {
      // 预载池里有该下标的画面就直接使用 (滑动时可见下一帧)
      final slot = pool?.slotFor(index);
      final Widget content;
      if (slot != null) {
        // key 绑定到播放器实例: 槽位换播放器时强制重建画面 widget,
        // 避免复用旧的订阅 / 可见性状态
        content = _MediaKitVideoSurface(
          key: ValueKey(slot.controller),
          controller: slot.controller,
        );
      } else if (index == currentFeedIndex) {
        content = const _FeedVideo();
      } else {
        content = const ColoredBox(color: Colors.black);
      }
      // 页面级滚轮注册: 先于 PageView 的 Scrollable 抢到事件 (详见 registerWheel)
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: registerWheel,
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
        onPointerDown: (_) => isDragging.value = true,
        onPointerUp: (_) => isDragging.value = false,
        onPointerCancel: (_) => isDragging.value = false,
        // 覆盖层 (底部信息 / 按钮) 挡住页面级滚轮时, 由此处兜底
        onPointerSignal: registerWheel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _togglePlay(context),
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
                      // 仅在非拖动阶段提交, 避免拖动途中切换播放
                      if (!isDragging.value) commitPage(page);
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
              // 长按倍速指示
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: isLongPress.value
                        ? Center(
                            child: Container(
                              key: const ValueKey('speed-hint'),
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 18, 12),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.fast_forward_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${useAppStore().state.longPressSpeed}x',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-speed-hint')),
                  ),
                ),
              ),
              // 底部信息与进度条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _FeedFooter(
                  items: items,
                  currentFeedIndex: currentFeedIndex,
                  scrubPreview: scrubPreview,
                  progressBar: _FeedProgressBar(
                    scrubPreview: scrubPreview,
                    onScrubStart: scrubStart,
                    onScrubSeek: scrubSeek,
                    onScrubEnd: scrubEnd,
                    onTapSeek: (target) => player.seek(target),
                  ),
                ),
              ),
              // 退出按钮
              Positioned(
                left: 8,
                top: 8,
                child: _FeedIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: t.exit_short_video_mode,
                  onPressed: exitShortVideoMode,
                ),
              ),
              // 右侧操作
              Positioned(
                right: 10,
                bottom: 110,
                child: _FeedActions(
                  volumePreview: volumePreview,
                  onVolumeAdjustStart: volumeAdjustStart,
                  onVolumeAdjustUpdate: volumeAdjustUpdate,
                  onVolumeAdjustEnd: volumeAdjustEnd,
                ),
              ),
              // 音量调节指示 (长按音量按钮上下滑动时显示)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<double?>(
                    valueListenable: volumePreview,
                    builder: (context, preview, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: preview == null
                          ? const SizedBox.shrink(
                              key: ValueKey('no-volume-hint'))
                          : Center(
                              key: const ValueKey('volume-hint'),
                              child: _FeedVolumeIndicator(volume: preview),
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

/// 当前页视频画面 (无预载池时的回退路径, 也用于 FVP 后端)
class _FeedVideo extends StatelessWidget {
  const _FeedVideo();

  @override
  Widget build(BuildContext context) {
    final player = context.read<MediaPlayer>();
    return SizedBox.expand(
      child: switch (player) {
        MediaKitPlayer player =>
          _MediaKitVideoSurface(controller: player.controller),
        FvpPlayer player => player.width == 0 || player.height == 0
            ? const SizedBox.shrink()
            : FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: player.width,
                  height: player.height,
                  child: VideoPlayer(player.controller),
                ),
              ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// Media Kit 视频画面 (始终 contain 适配)
class _MediaKitVideoSurface extends StatelessWidget {
  const _MediaKitVideoSurface({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        // 短视频流不显示字幕 (池内已关闭字幕轨, 这里再关掉字幕层)
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
        fit: BoxFit.contain,
      ),
    );
  }
}

/// 右侧操作按钮列
class _FeedActions extends HookWidget {
  const _FeedActions({
    required this.volumePreview,
    required this.onVolumeAdjustStart,
    required this.onVolumeAdjustUpdate,
    required this.onVolumeAdjustEnd,
  });

  final ValueNotifier<double?> volumePreview;
  final void Function(Offset globalPosition) onVolumeAdjustStart;
  final void Function(Offset globalPosition) onVolumeAdjustUpdate;
  final void Function() onVolumeAdjustEnd;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: t.play_pause,
          onPressed: () => _togglePlay(context),
        ),
        const SizedBox(height: 12),
        _FeedIconButton(
          icon: Icons.photo_camera_rounded,
          tooltip: t.screenshot,
          onPressed: () => takeScreenshot(context, context.read<MediaPlayer>()),
        ),
        const SizedBox(height: 12),
        _FeedVolumeButton(
          volumePreview: volumePreview,
          onAdjustStart: onVolumeAdjustStart,
          onAdjustUpdate: onVolumeAdjustUpdate,
          onAdjustEnd: onVolumeAdjustEnd,
        ),
      ],
    );
  }
}

/// 音量按钮: 点击 = 静音 / 取消静音 (音量 0 时恢复 80);
/// 长按后上下滑动 = 调节音量 (仅按住按钮时生效, 不影响翻页 / 倍速 / 播放暂停)。
class _FeedVolumeButton extends HookWidget {
  const _FeedVolumeButton({
    required this.volumePreview,
    required this.onAdjustStart,
    required this.onAdjustUpdate,
    required this.onAdjustEnd,
  });

  final ValueNotifier<double?> volumePreview;
  final void Function(Offset globalPosition) onAdjustStart;
  final void Function(Offset globalPosition) onAdjustUpdate;
  final void Function() onAdjustEnd;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final volume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);
    final adjusting = useState(false);

    return MergeSemantics(
      child: Semantics(
        label: t.volume,
        child: GestureDetector(
          // 在按钮上按住后上下滑动: 由长按识别器接管指针,
          // PageView 的翻页 / 外层的手势都会在竞争中被拒绝
          onLongPressStart: (details) {
            adjusting.value = true;
            onAdjustStart(details.globalPosition);
          },
          onLongPressMoveUpdate: (details) {
            if (adjusting.value) onAdjustUpdate(details.globalPosition);
          },
          onLongPressEnd: (_) {
            adjusting.value = false;
            onAdjustEnd();
          },
          onLongPressCancel: () {
            adjusting.value = false;
            onAdjustEnd();
          },
          child: Listener(
            // PC: 指针悬停在按钮上滚轮 = 微调音量 (拦截并取代翻页)
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) return;
              GestureBinding.instance.pointerSignalResolver
                  .register(event, (resolved) {
                final scrollEvent = resolved as PointerScrollEvent;
                final dy = scrollEvent.scrollDelta.dy;
                if (dy == 0) return;
                if (useAppStore().state.isMuted) {
                  useAppStore().updateMute(false);
                }
                // 一格 (约 100px) 约 5% (1~10 之间)
                final step = (dy.abs() / 20).ceil().clamp(1, 10);
                final current = useAppStore().state.volume;
                useAppStore().updateVolume(dy < 0 ? current + step : current - step);
              });
            },
            child: ValueListenableBuilder<double?>(
              valueListenable: volumePreview,
              builder: (context, preview, _) {
                final level = (preview ?? volume.toDouble()).round();
                return Material(
                  color: adjusting.value ? Colors.black54 : Colors.black38,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: Icon(
                      isMuted || level == 0
                          ? Icons.volume_off_rounded
                          : level < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: () {
                      if (volume == 0) {
                        useAppStore().updateVolume(80);
                      } else {
                        useAppStore().toggleMute();
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 音量调节指示 (长按滑动时显示在画面中央)
class _FeedVolumeIndicator extends StatelessWidget {
  const _FeedVolumeIndicator({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) {
    final level = volume.round();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            level == 0
                ? Icons.volume_off_rounded
                : level < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            '$level%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部标题 / 序号 / 时间与可拖拽进度条。
/// 渐变背景覆盖整个底部区域 (含进度条), 与视频明暗衔接自然。
class _FeedFooter extends HookWidget {
  const _FeedFooter({
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
class _FeedProgressBar extends HookWidget {
  const _FeedProgressBar({
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
class _FeedIconButton extends StatelessWidget {
  const _FeedIconButton({
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