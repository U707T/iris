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
  if (player.isPlaying) {
    player.pause();
  } else {
    player.play();
  }
}

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

    // 双击快进 / 快退
    void onDoubleTapDown(TapDownDetails details) {
      final seekStep = useAppStore().state.seekStepSeconds;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final tapDx = details.globalPosition.dx;

      if (tapDx > screenWidth * 0.75) {
        player.forward(seekStep);
      } else if (tapDx < screenWidth * 0.25) {
        player.backward(seekStep);
      } else {
        _togglePlay(context);
      }
    }

    // 长按加速播放
    final rateBeforeLongPress = useRef<double?>(null);
    final isLongPress = useState(false);

    void onLongPressStart(LongPressStartDetails details) {
      if (!player.isPlaying) return;
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
      scrubResume.value = player.isPlaying;
      if (scrubResume.value) player.pause();
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
      scrubState.value = (
        active: true,
        start: player.position,
        startDx: details.globalPosition.dx,
      );
      scrubStart(player.position);
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
    final wheelCooldown = useRef<DateTime?>(null);

    void registerWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
        final scrollEvent = resolved as PointerScrollEvent;
        final dy = scrollEvent.scrollDelta.dy;
        // 忽略高精度滚轮 / 触控板的微小增量
        if (dy.abs() < 4) return;
        final now = DateTime.now();
        final last = wheelCooldown.value;
        // 冷却期内的事件直接丢弃, 避免快速滚动一次跳过太多视频
        if (last != null &&
            now.difference(last) < const Duration(milliseconds: 420)) {
          return;
        }
        wheelCooldown.value = now;
        moveShortVideoBy(dy > 0 ? 1 : -1);
      });
    }

    Widget buildPage(BuildContext context, int index) {
      // 预载池里有该下标的画面就直接使用 (滑动时可见下一帧)
      final slot = pool?.slotFor(index);
      final Widget content;
      if (slot != null) {
        content = _MediaKitVideoSurface(controller: slot.controller);
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
              const Positioned(
                right: 10,
                bottom: 110,
                child: _FeedActions(),
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
  const _MediaKitVideoSurface({required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// 右侧操作按钮列
class _FeedActions extends HookWidget {
  const _FeedActions();

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
      ],
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