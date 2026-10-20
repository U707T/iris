import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/use_app_lifecycle.dart';
import 'package:iris/hooks/use_cover.dart';
import 'package:iris/hooks/use_keyboard.dart';
import 'package:iris/info.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/audio.dart';
import 'package:iris/pages/player/overlays/controls_overlay.dart';
import 'package:iris/pages/player/overlays/gesture_overlay.dart';
import 'package:iris/pages/player/overlays/minimal_progress_overlay.dart';
import 'package:iris/pages/player/overlays/playback_error_overlay.dart';
import 'package:iris/pages/player/overlays/stats_overlay.dart';
import 'package:iris/pages/player/short_video/short_video_view.dart';
import 'package:iris/pages/player/video_view.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/drop_queue.dart';
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

    final controlHideTimer = useRef<Timer?>(null);
    final progressHideTimer = useRef<Timer?>(null);

    final fit = useAppStore().select(context, (state) => state.fit);
    final bool autoHideControls =
        useAppStore().select(context, (state) => state.autoHideControls);
    final int controlHideDelaySeconds =
        useAppStore().select(context, (state) => state.controlHideDelaySeconds);
    final isShortVideoMode =
        usePlayerUiStore().select(context, (state) => state.isShortVideoMode);
    final playbackError =
        context.select<MediaPlayer, String?>((player) => player.error);

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

    void startControlHideTimer() {
      controlHideTimer.value?.cancel();
      // 设置里关掉自动隐藏后, 控制栏只在点击画面时手动收/放
      if (!autoHideControls) return;
      controlHideTimer.value = Timer(
        Duration(seconds: controlHideDelaySeconds),
        () {
          if (usePlayerUiStore().state.isShowControl &&
              !usePlayerUiStore().state.isHovering) {
            usePlayerUiStore().updateIsShowControl(false);
          }
        },
      );
    }

    void startProgressHideTimer() {
      progressHideTimer.value?.cancel();
      if (!autoHideControls) return;
      progressHideTimer.value = Timer(
        Duration(seconds: controlHideDelaySeconds),
        () {
          if (usePlayerUiStore().state.isShowProgress) {
            usePlayerUiStore().updateIsShowProgress(false);
          }
        },
      );
    }

    void resetControlHideTimer() {
      controlHideTimer.value?.cancel();
      startControlHideTimer();
    }

    void resetBottomProgressTimer() {
      progressHideTimer.value?.cancel();
      startProgressHideTimer();
    }

    void showControl() {
      usePlayerUiStore().updateIsShowControl(true);
      // 不要在这里重置 isHovering: 悬停回调会先置 true 再调 showControl,
      // 重置会把"指针停在控制栏上"的状态抹掉, 5 秒后控制栏照样消失。
      resetControlHideTimer();
    }

    void hideControl() {
      usePlayerUiStore().updateIsShowControl(false);
      usePlayerUiStore().updateIsHovering(false);
      controlHideTimer.value?.cancel();
    }

    Future<void> showControlForHover(Future<void> callback) async {
      try {
        context.read<MediaPlayer>().saveProgress();
        showControl();
        usePlayerUiStore().updateIsHovering(true);
        await callback;
        // 弹层关闭后没人在鼠标事件里复位, 这里显式收尾
        usePlayerUiStore().updateIsHovering(false);
        showControl();
      } catch (e) {
        logger(e.toString());
      }
    }

    void showProgress() {
      usePlayerUiStore().updateIsShowProgress(true);
      resetBottomProgressTimer();
    }

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
        hideControl();
        usePlayerUiStore().updateIsShowProgress(false);
        return;
      }

      if (isDesktop && uiState.isFullScreen) {
        await usePlayerUiStore().updateFullScreen(false);
        return;
      }

      // 二次确认退出
      if (isExitConfirm.value) {
        await context.read<MediaPlayer>().saveProgress();
        if (isDesktop) {
          windowManager.close();
        } else {
          SystemNavigator.pop();
          exit(0);
        }
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
      startControlHideTimer();
      return () => controlHideTimer.value?.cancel();
    }, [autoHideControls, controlHideDelaySeconds]);

    useEffect(() {
      return () => progressHideTimer.value?.cancel();
    }, []);

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
                    hideControl: hideControl,
                    showProgress: showProgress,
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
