import 'package:iris/pages/player/short_video/short_video_pager.dart';
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

    final playQueue = usePlayQueueStore().select(
      context,
      (state) => state.playQueue,
    );
    final currentIndex = usePlayQueueStore().select(
      context,
      (state) => state.currentIndex,
    );

    // 短视频流 = 播放队列中的视频条目 (跳过音频)
    final items = useMemoized(() => getVideoItems(playQueue), [playQueue]);
    final currentFeedIndex = useMemoized(
      () => items.indexWhere((item) => item.index == currentIndex),
      [items, currentIndex],
    );

    // 队列为空 / 当前项不是视频时 (如打开了音频), 自动退出短视频模式
    final exitRequested = useRef(false);
    useEffect(() {
      if (items.isEmpty || currentFeedIndex < 0) {
        if (!exitRequested.value) {
          exitRequested.value = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => exitShortVideoMode(),
          );
        }
      }
      return;
    }, [items, currentFeedIndex]);

    final isInitializing = context.select<MediaPlayer, bool>(
      (player) => player.isInitializing,
    );
    final playbackError = context.select<MediaPlayer, String?>(
      (player) => player.error,
    );

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
      () => ShortVideoWheelSwitcher(onSwitch: moveShortVideoBy),
      [],
    );

    Widget buildPage(BuildContext context, int index) {
      // Only this page's assigned media may appear; a recycled slot can still
      // contain the previous video's native texture while its new open runs.
      final Widget content = pool != null
          ? ShortVideoPoolPage(
              slot: pool.slotFor(index),
              item: items[index],
              feedIndex: index,
            )
          : index == currentFeedIndex
          ? const ShortVideoFeedVideo()
          : const ColoredBox(color: Colors.black);
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
        // 覆盖层 (底部信息 / 按钮) 挡住页面级滚轮时, 由此处兜底
        onPointerSignal: wheel.register,
        child: PlayerGestureLayer(
          readPlayer: () => context.read<MediaPlayer>(),
          seekStepSeconds: () => useAppStore().state.seekStepSeconds,
          // 纵向留给 PageView 翻页；横滑 = 进度（与主窗口同一套阈值）
          allowVertical: false,
          // 短视频的单击是「播放 / 暂停」, 有副作用: 推迟到双击窗口结束,
          // 否则双击中间 1/3 会先暂停再播放 (能听见一次多余的停顿)
          deferSingleTap: () => true,
          onTap: () => toggleShortVideoPlay(context),
          // 双击中间 1/3 = 播放暂停（与主窗口一致）
          onDoubleTapMiddle: () => toggleShortVideoPlay(context),
          onLongPressStart: onLongPressStart,
          onLongPressEnd: onLongPressEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShortVideoPager(
                currentIndex: currentFeedIndex,
                itemCount: items.length,
                itemBuilder: buildPage,
                onPageSettled: commitPage,
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
                              key: ValueKey('no-volume-hint'),
                            )
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
