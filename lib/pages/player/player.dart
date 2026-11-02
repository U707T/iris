import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/use_app_lifecycle.dart';
import 'package:iris/hooks/use_cover.dart';
import 'package:iris/hooks/use_keyboard.dart';
import 'package:iris/info.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/audio.dart';
import 'package:iris/pages/player/overlays/controls_auto_hide.dart';
import 'package:iris/pages/player/overlays/controls_overlay.dart';
import 'package:iris/pages/player/overlays/gesture_overlay.dart';
import 'package:iris/pages/player/overlays/minimal_progress_overlay.dart';
import 'package:iris/pages/player/overlays/playback_error_overlay.dart';
import 'package:iris/pages/player/overlays/stats_overlay.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_hud.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/pages/player/video_view.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/drop_queue.dart';
import 'package:iris/utils/exit_app.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:iris/utils/short_video.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class Player extends HookWidget {
  const Player({super.key});

  @override
  Widget build(BuildContext context) {
    final width = context.select<MediaPlayer, double>((player) => player.width);
    final height =
        context.select<MediaPlayer, double>((player) => player.height);

    useAppLifecycle();

    final cover = useCover();

    final fit = useAppStore().select(context, (state) => state.fit);
    final bool autoHideControls =
        useAppStore().select(context, (state) => state.autoHideControls);
    final int controlHideDelaySeconds =
        useAppStore().select(context, (state) => state.controlHideDelaySeconds);
    final isShortVideoMode =
        usePlayerUiStore().select(context, (state) => state.isShortVideoMode);
    final isSeeking =
        usePlayerUiStore().select(context, (state) => state.isSeeking);
    final isHovering =
        usePlayerUiStore().select(context, (state) => state.isHovering);
    final isPlaying =
        context.select<MediaPlayer, bool>((player) => player.isPlaying);
    final playbackError =
        context.select<MediaPlayer, String?>((player) => player.error);

    // 弹层 / 菜单 / 对话框盖在播放器上时, 本页不再是 current route。
    // 用它统一判断「现在有东西压在控制栏上面」: 一处覆盖所有入口
    // (弹出菜单 / 播放队列 / 设置 / 关于 / 快捷键 / 音量 popover ...),
    // 不再靠每个按钮自己记得先置 isHovering。
    final bool isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    final playQueue =
        usePlayQueueStore().select(context, (state) => state.playQueue);
    final currentIndex =
        usePlayQueueStore().select(context, (state) => state.currentIndex);

    final int currentPlayIndex = useMemoized(
        () => playQueue.indexWhere((element) => element.index == currentIndex),
        [playQueue, currentIndex]);

    final FileItem? file = useMemoized(
        () => playQueue.isEmpty || currentPlayIndex < 0
            ? null
            : playQueue[currentPlayIndex].file,
        [playQueue, currentPlayIndex]);

    final title = useMemoized(
        () => file != null
            ? playQueue.length > 1
                ? '[${currentPlayIndex + 1}/${playQueue.length}] ${file.name}'
                : file.name
            : INFO.title,
        [file, currentPlayIndex, playQueue]);

    final focusNode = useFocusNode();

    useEffect(() {
      focusNode.requestFocus();
      return;
    }, []);

    // 控制栏 / 迷你进度的显隐调度: 规则见 controls_auto_hide.dart
    final controlsAutoHide = useMemoized(
      () => ControlsAutoHide(
        readControls: () => usePlayerUiStore().state.isShowControl,
        writeControls: usePlayerUiStore().updateIsShowControl,
        readMinimal: () => usePlayerUiStore().state.isShowProgress,
        writeMinimal: usePlayerUiStore().updateIsShowProgress,
      ),
      const [],
    );

    // 音频没有画面可看, 控制栏一直留着; 出错时把控制栏留给用户去重试。
    // 两者都按「不在播放」处理, 于是不会进入倒计时 —— 界面与 store 状态一致。
    final bool autoHideEligible =
        isPlaying && file?.type == ContentType.video && playbackError == null;

    useEffect(() {
      controlsAutoHide
        ..delay = Duration(seconds: controlHideDelaySeconds)
        ..enabled = autoHideControls
        ..playing = autoHideEligible
        ..seeking = isSeeking
        ..hovering = isHovering
        ..overlayOpen = !isRouteCurrent
        ..active = !isShortVideoMode
        ..sync();
      return;
    }, [
      controlsAutoHide,
      autoHideControls,
      controlHideDelaySeconds,
      autoHideEligible,
      isSeeking,
      isHovering,
      isRouteCurrent,
      isShortVideoMode,
    ]);

    useEffect(() {
      return controlsAutoHide.dispose;
    }, [controlsAutoHide]);

    void showControl() => controlsAutoHide.show();

    void hideControl() => controlsAutoHide.hide();

    /// 唤出并重新计时, 但**不**改变悬停状态: 悬停回调会先置 isHovering,
    /// 这里再把它抹掉的话, 指针停在控制栏上也会被计时器收走。
    Future<void> showControlForHover(Future<void> callback) async {
      try {
        await context.read<MediaPlayer>().saveProgress();
        showControl();
        await callback;
      } catch (e) {
        logger(e.toString());
      } finally {
        // 弹层关闭 / 抛异常都要重新计时 (overlayOpen 由路由状态自己维护)
        showControl();
      }
    }

    void showProgress() => controlsAutoHide.showMinimal();

    // 播放 -> 暂停 / 播完: 把控制栏放回来 (YouTube / VLC / mpv 一致)。
    // 暂停后画面静止, 用户下一步大概率要看进度或调音量, 让人先点一下画面
    // 才能看到控制栏是没必要的一步。
    //
    // 注意排除「拖动 seek 造成的临时暂停」: `SeekSession.start` 会先 pause 再续播,
    // 那不是用户按了暂停 —— 横滑时该出现的只有底部的瞬时进度读数, 不是整套控制栏。
    // 判定用 isSeeking + 共享预览值: 两者都在拖动开始时同步置位, 早于播放器
    // 暂停事件（异步流）到达, 所以不会被误判。
    final wasPlaying = useRef(isPlaying);
    useEffect(() {
      final pausedBySeek = isSeeking || seekHub.preview.value != null;
      if (wasPlaying.value && !isPlaying && !isShortVideoMode && !pausedBySeek) {
        showControl();
      }
      wasPlaying.value = isPlaying;
      return;
    }, [isPlaying, isShortVideoMode, isSeeking]);

    // 换片时把控制栏叫回来 (主流播放器一致): 刚打开的媒体应该能马上看到进度与标题,
    // 而不是沿用上一条留下的「已收起」状态。
    useEffect(() {
      if (file == null) return;
      showControl();
      return;
    }, [file?.uri]);

    // Android 返回手势 / 返回键:
    // 1. 短视频模式中 -> 先退出短视频模式
    // 2. 有弹层/对话框时, 交给它们自己处理 (由 Navigator 自动分发)
    // 3. 控制栏显示中 -> 先收起控制栏
    // 4. 全屏中 -> 先退出全屏
    // 5. 否则 -> 二次确认退出应用
    final exitConfirmTimer = useRef<Timer?>(null);
    final isExitConfirm = useState(false);

    useEffect(() {
      return () => exitConfirmTimer.value?.cancel();
    }, []);

    Future<void> handleSystemBack() async {
      final uiState = usePlayerUiStore().state;

      if (uiState.isShortVideoMode) {
        exitShortVideoMode();
        return;
      }

      if (uiState.isShowControl || uiState.isShowProgress) {
        // hide 会把迷你进度一起收掉
        hideControl();
        return;
      }

      if (isDesktop && uiState.isFullScreen) {
        await usePlayerUiStore().updateFullScreen(false);
        return;
      }

      // 二次确认退出
      if (isExitConfirm.value) {
        await exitApp(context.read<MediaPlayer>());
        return;
      }

      isExitConfirm.value = true;
      exitConfirmTimer.value?.cancel();
      exitConfirmTimer.value = Timer(const Duration(seconds: 2), () {
        isExitConfirm.value = false;
      });
    }

    final onKeyEvent = useKeyboard(
      showControl: showControl,
      showControlForHover: showControlForHover,
      showProgress: showProgress,
    );

    useEffect(() {
      if (isDesktop) {
        windowManager.setTitle(title);
      }
      return;
    }, [title]);

    final Size windowSize = useMemoized(
        () => MediaQuery.sizeOf(context), [MediaQuery.sizeOf(context)]);

    final scaleFactor = useMemoized(
      () => View.of(context).physicalSize.width / windowSize.width,
      [View.of(context).physicalSize.width],
    );

    final videoViewSize = useMemoized(() {
      if (fit != BoxFit.none || width == 0 || height == 0) {
        return windowSize;
      } else {
        return Size(width / scaleFactor, height / scaleFactor);
      }
    }, [fit, windowSize, width, height, scaleFactor]);

    final videoViewOffset = useMemoized(
        () => fit == BoxFit.none
            ? Offset(
                (windowSize.width - videoViewSize.width) / 2,
                (windowSize.height - videoViewSize.height) / 2,
              )
            : Offset(0, 0),
        [fit, windowSize, videoViewSize]);

    return DropTarget(
      onDragDone: (details) async {
        // 直接用拖入列表建队列 (跨目录拖入不再丢文件,
        // currentIndex 也不会指向被过滤掉的条目)
        final playQueue =
            buildDropPlayQueue(details.files.map((file) => file.path));
        if (playQueue == null || playQueue.playQueue.isEmpty) return;

        useAppStore().updateAutoPlay(true);
        usePlayQueueStore().update(
          playQueue: playQueue.playQueue,
          index: playQueue.currentIndex,
        );
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;
          await handleSystemBack();
        },
        child: KeyboardListener(
          focusNode: focusNode,
          onKeyEvent: onKeyEvent,
          child: Stack(
            children: [
              if (isShortVideoMode)
                // 短视频模式 (类抖音竖向信息流)
                const Positioned.fill(
                  child: ShortVideoView(),
                )
              else ...[
                // Video
                Positioned(
                  left: videoViewOffset.dx,
                  top: videoViewOffset.dy,
                  width: videoViewSize.width,
                  height: videoViewSize.height,
                  child: VideoView(
                    key: ValueKey(file?.uri),
                    fit: fit,
                  ),
                ),
                Positioned.fill(
                  child: MinimalProgressOverlay(
                    title: title,
                    file: file,
                  ),
                ),
                // Audio
                if (file?.type == ContentType.audio)
                  Positioned.fill(
                    child: Audio(cover: cover),
                  ),
                Positioned.fill(
                  child: GestureOverlay(
                    showControl: showControl,
                    hideControl: hideControl,
                    showProgress: showProgress,
                  ),
                ),
              ],
              // 快进 / 快退提示 (双击步长 + 拖动读数): 两个模式共用同一份,
              // 放在分支之外, 主窗口与短视频模式的视觉/文案完全一致。
              Positioned.fill(
                child: SeekHudOverlay(controller: seekHub.hud),
              ),
              // 播放统计 OSD (短视频模式没有统计源, 不显示, 免得开出一个空面板)
              if (!isShortVideoMode &&
                  usePlayerUiStore()
                      .select(context, (state) => state.isShowStats))
                const StatsOverlay(),
              // 退出确认提示 (Android 返回键二次确认)
              if (isExitConfirm.value)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          getLocalizations(context).exit_app_back_again,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isShortVideoMode)
                Positioned.fill(
                  child: ControlsOverlay(
                    file: file,
                    title: title,
                    showControl: showControl,
                    showControlForHover: showControlForHover,
                  ),
                ),
              // 播放失败提示 (装载超时 / 解码失败 / 网络错误)
              if (!isShortVideoMode && playbackError != null)
                Positioned.fill(
                  child: PlaybackErrorOverlay(
                    fileName: file?.name,
                    onRetry: () => context.read<MediaPlayer>().play(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
