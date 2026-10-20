import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/wait_for_first_frame.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 普通模式播放器的引擎层：Player / VideoController 生命周期、装载会话、
/// 当前文件。
///
/// 只负责 open 的时序（视频输出就绪 -> 暂停 open -> 首帧 -> 播放），
/// 不碰 UI 快照与进度存档（见 `use_player_streams.dart` /
/// `use_player_progress.dart`）。短视频模式有自己的一套（预载池），但 open
/// 时序与"会话过期就丢弃"的规则保持一致。
class PlayerEngine {
  PlayerEngine({
    required this.player,
    required this.controller,
    required this.playQueue,
    required this.currentPlayIndex,
    required this.file,
    required this.isInitializing,
    required this.error,
    required this.init,
  });

  final Player player;
  final VideoController controller;
  final List<PlayQueueItem> playQueue;
  final int currentPlayIndex;
  final FileItem? file;
  final bool isInitializing;
  final String? error;
  final Future<void> Function(FileItem file) init;
}

PlayerEngine usePlayerEngine(BuildContext context) {
  final player = useMemoized(
    () => Player(
      // 字幕功能已移除: 关闭 libass 渲染 (Android 上 libass 依赖内置字体,
      // 没有字体时内嵌字幕会渲染成方块)。画面上的字幕层另外也已关闭,
      // 见 video_view.dart 的 SubtitleViewConfiguration。
      configuration: const PlayerConfiguration(
        libass: false,
      ),
    ),
  );

  final controller = useMemoized(() => VideoController(player));

  final rate = useAppStore().select(context, (state) => state.rate);
  final volume = useAppStore().select(context, (state) => state.volume);
  final isMuted = useAppStore().select(context, (state) => state.isMuted);

  useEffect(() {
    player.setRate(rate);
    player.setVolume(isMuted ? 0 : volume.toDouble());
    return () {
      // 先立即静音再异步销毁: dispose 内部要等播放器初始化 / 视频输出就绪,
      // 可能明显滞后 (切换模式时旧播放器继续出声的根因之一)
      unawaited(player.stop().catchError((_) {}));
      unawaited(player.dispose().catchError((_) {}));
    };
  }, const []);

  final List<PlayQueueItem> playQueue =
      usePlayQueueStore().select(context, (state) => state.playQueue);
  final int currentIndex =
      usePlayQueueStore().select(context, (state) => state.currentIndex);
  final bool autoPlay =
      useAppStore().select(context, (state) => state.autoPlay);

  final int currentPlayIndex = useMemoized(
      () => playQueue.indexWhere((element) => element.index == currentIndex),
      [playQueue, currentIndex]);

  final FileItem? file = useMemoized(
      () => playQueue.isEmpty || currentPlayIndex < 0
          ? null
          : playQueue[currentPlayIndex].file,
      [playQueue, currentPlayIndex]);

  final isInitializing = useState(false);

  /// 装载 / 播放失败原因 (null = 正常)。给 UI 一个出口:
  /// release 下 logger 不输出, 只靠日志等于让用户看黑屏。
  final error = useState<String?>(null);

  /// 装载会话: 每次 init 递增, 用于丢弃过期的异步结果
  final openSession = useRef(0);

  Future<void> init(FileItem file) async {
    if (file.uri == '') return;
    final session = ++openSession.value;
    isInitializing.value = true;
    error.value = null;

    bool isCurrent() => session == openSession.value;

    try {
      // 视频输出先于 open 就绪: 二者并行初始化时, 若视频先打开, 包内基于
      // videoParams 的画面尺寸同步会丢失, 画面会一直按初始的 1x1 比例显示
      // (带超时兜底, 视频输出不可用时也不能把 open 卡死)
      try {
        await controller.platform.future.timeout(const Duration(seconds: 2));
      } catch (e) {
        logger('Video output not ready: $e');
      }
      // 等待期间可能已切到别的文件: 不要再把旧文件 open 进来
      if (!isCurrent()) return;

      final storage = useStorageStore().findById(file.storageId);
      final auth = storage?.getAuth();
      logger('Open file: $file');
      // 视频: 先以暂停方式打开, 等首帧渲染出来再开始播放 —— 否则音频会先出声,
      // 画面还黑着 (视频输出 / 首帧解码比音频慢)
      final waitFirstFrame = autoPlay && file.type == ContentType.video;
      await player
          .open(
            Media(
              file.uri,
              httpHeaders: auth != null ? {'authorization': auth} : {},
            ),
            play: autoPlay && !waitFirstFrame,
          )
          .timeout(const Duration(seconds: 15));
      // open 走的是播放器内部锁: 旧文件的 open 晚于新文件落地会把当前画面顶掉
      if (!isCurrent()) return;

      if (waitFirstFrame) {
        await waitForFirstFrame(controller);
        // 等待期间用户可能已暂停 / 已切换文件: 这时不要抢回播放
        if (!isCurrent()) return;
        if (useAppStore().state.autoPlay) {
          await player.play();
        }
      }
    } on TimeoutException {
      logger('Open file timed out: ${file.uri}');
      if (isCurrent()) {
        error.value = 'timeout';
        unawaited(player.stop().catchError((_) {}));
      }
    } catch (e) {
      logger('Error initializing player: $e');
      if (isCurrent()) error.value = e.toString();
    } finally {
      // 已有更新的装载在进行时, 由它负责收尾 (避免提前熄灭加载指示)
      if (isCurrent()) isInitializing.value = false;
    }
  }

  useEffect(() {
    if (file == null || playQueue.isEmpty) {
      player.stop();
    } else {
      init(file);
    }
    return;
  }, [file]);

  return PlayerEngine(
    player: player,
    controller: controller,
    playQueue: playQueue,
    currentPlayIndex: currentPlayIndex,
    file: file,
    isInitializing: isInitializing.value,
    error: error.value,
    init: init,
  );
}
