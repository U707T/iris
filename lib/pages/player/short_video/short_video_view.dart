import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
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
class ShortVideoView extends HookWidget {
  const ShortVideoView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

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
      final player = context.read<MediaPlayer>();
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

    void onLongPressStart(LongPressStartDetails details) {
      if (!context.read<MediaPlayer>().isPlaying) return;
      rateBeforeLongPress.value = useAppStore().state.rate;
      useAppStore().updateRate(
        useAppStore().state.longPressSpeed,
        persist: false,
      );
    }

    void onLongPressEnd() {
      final restoreRate = rateBeforeLongPress.value;
      if (restoreRate == null) return;
      useAppStore().updateRate(restoreRate, persist: false);
      rateBeforeLongPress.value = null;
    }

    // 水平拖动调节进度
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
        start: context.read<MediaPlayer>().position,
        startDx: details.globalPosition.dx,
      );
      usePlayerUiStore().updateIsSeeking(true);
    }

    void onHorizontalDragUpdate(DragUpdateDetails details) {
      if (!scrubState.value.active) return;
      final totalDx = details.globalPosition.dx - scrubState.value.startDx;
      const double sensitivity = 3.0; // 每滑动 3 像素代表 1 秒
      final target = scrubState.value.start +
          Duration(milliseconds: (totalDx / sensitivity * 1000).round());
      context.read<MediaPlayer>().seek(target);
    }

    void onHorizontalDragEnd() {
      if (!scrubState.value.active) return;
      scrubState.value = (active: false, start: Duration.zero, startDx: 0.0);
      usePlayerUiStore().updateIsSeeking(false);
    }

    // 鼠标滚轮切换上 / 下一条 (接管 PageView 默认的滚轮行为)
    final wheelCooldown = useRef<DateTime?>(null);

    void registerWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
        final scrollEvent = resolved as PointerScrollEvent;
        final dy = scrollEvent.scrollDelta.dy;
        if (dy.abs() < 4) return;
        final now = DateTime.now();
        final last = wheelCooldown.value;
        if (last != null &&
            now.difference(last) < const Duration(milliseconds: 420)) {
          return;
        }
        wheelCooldown.value = now;
        moveShortVideoBy(dy > 0 ? 1 : -1);
      });
    }

    Widget buildPage(BuildContext context, int index) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: registerWheel,
        child: index == currentFeedIndex
            ? const _FeedVideo()
            : const ColoredBox(color: Colors.black),
      );
    }

    if (items.isEmpty || currentFeedIndex < 0) {
      return const SizedBox.shrink();
    }

    return Listener(
      onPointerDown: (_) => isDragging.value = true,
      onPointerUp: (_) => isDragging.value = false,
      onPointerCancel: (_) => isDragging.value = false,
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
            if (isInitializing)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            // 底部信息与进度
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _FeedFooter(
                  items: items,
                  currentFeedIndex: currentFeedIndex,
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
    );
  }
}

/// 当前页视频画面 (始终使用 contain 适配, 不跟随全局缩放 / 旋转)
class _FeedVideo extends StatelessWidget {
  const _FeedVideo();

  @override
  Widget build(BuildContext context) {
    final player = context.read<MediaPlayer>();
    return SizedBox.expand(
      child: switch (player) {
        MediaKitPlayer player => Video(
            controller: player.controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
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

/// 底部标题 / 序号 / 时间与细进度条
class _FeedFooter extends HookWidget {
  const _FeedFooter({
    required this.items,
    required this.currentFeedIndex,
  });

  final List<PlayQueueItem> items;
  final int currentFeedIndex;

  @override
  Widget build(BuildContext context) {
    final position =
        context.select<MediaPlayer, Duration>((player) => player.position);
    final duration =
        context.select<MediaPlayer, Duration>((player) => player.duration);
    final isSeeking =
        usePlayerUiStore().select(context, (state) => state.isSeeking);

    final double progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;

    final TextStyle metaStyle = TextStyle(
      color: Colors.white.withValues(alpha: isSeeking ? 1.0 : 0.7),
      fontSize: 12,
      decoration: TextDecoration.none,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 40, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
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
              Row(
                children: [
                  Text(
                    '${currentFeedIndex + 1}/${items.length}',
                    style: metaStyle,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${formatDurationToMinutes(position)} / ${formatDurationToMinutes(duration)}',
                    style: metaStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: progress,
          minHeight: 2.5,
          backgroundColor: Colors.white24,
          color: Colors.white,
        ),
      ],
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
