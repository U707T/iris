import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/player/use_auto_next.dart';
import 'package:iris/hooks/player/use_player_engine.dart';
import 'package:iris/hooks/player/use_player_progress.dart';
import 'package:iris/hooks/player/use_player_stats.dart';
import 'package:iris/hooks/player/use_player_streams.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:media_kit/media_kit.dart';

/// 普通模式的 Media Kit 播放器。
///
/// 只做组装与"用户操作"（播放 / 暂停 / seek / 逐帧 / 截图）；
/// 具体职责拆在：
/// - `use_player_engine.dart`   生命周期、装载会话、当前文件、open 时序
/// - `use_player_streams.dart`  media_kit 流 -> 快照
/// - `use_player_progress.dart` 进度保存 / 恢复
/// - `use_player_stats.dart`    统计轮询
/// - `use_auto_next.dart`       播完连播
// 注意: MediaPlayer 是"本帧快照", position / duration 每次变化都会重建。
// 下面依赖表里的回调是每帧新建的闭包, 所以这不是跨帧缓存, 而是"跟着快照
// 刷新"的显式依赖表; 不要把它当成可复用对象去优化。
MediaKitPlayer useMediaKitPlayer(BuildContext context) {
  final engine = usePlayerEngine(context);
  final player = engine.player;
  final file = engine.file;

  final streams = usePlayerStreams(player);

  final rate = useAppStore().select(context, (state) => state.rate);
  final volume = useAppStore().select(context, (state) => state.volume);
  final isMuted = useAppStore().select(context, (state) => state.isMuted);
  final bool autoPlay =
      useAppStore().select(context, (state) => state.autoPlay);
  final Repeat repeat = useAppStore().select(context, (state) => state.repeat);
  final bool alwaysPlayFromBeginning =
      useAppStore().select(context, (state) => state.alwaysPlayFromBeginning);

  final history = useHistoryStore().select(context, (state) => state.history);

  final isShowStats =
      usePlayerUiStore().select(context, (state) => state.isShowStats);
  // 统计轮询独立成 hook (帧率 / 丢帧 / 解码器 / 缓存), 返回同步读取函数
  final getStats = usePlayerStats(player, isShowStats: isShowStats);

  final saveProgress = usePlayerProgress(
    player: player,
    file: file,
    duration: streams.duration,
    alwaysPlayFromBeginning: alwaysPlayFromBeginning,
    history: history,
  );

  // 播完自动连播（“下一条是谁”的规则见 queue_navigation.dart）
  useAutoNext(
    player: player,
    playQueue: engine.playQueue,
    currentPlayIndex: engine.currentPlayIndex,
    repeat: repeat,
    completed: streams.completed,
  );

  useEffect(() {
    player.setRate(rate);
    return;
  }, [rate]);

  useEffect(() {
    player.setVolume(isMuted ? 0 : volume.toDouble());
    return;
  }, [volume, isMuted]);

  // AppState 比队列晚加载完时, init 可能已经在 autoPlay=false 的状态下把
  // 文件打开了 (表现为"双击文件打开了, 却停在开头不播")。autoPlay 翻转成
  // true (或装载刚结束时) 补一次, 但只在"停在开头"时接管 ——
  // 用户中途暂停不会被抢回播放。
  useEffect(() {
    if (!autoPlay) return null;
    if (file == null || engine.isInitializing) return null;
    if (player.state.playing) return null;
    if (player.state.duration == Duration.zero) return null;
    if (player.state.position > const Duration(seconds: 1)) return null;
    unawaited(player.play().catchError((_) {}));
    return null;
    // isInitializing 也要进依赖: autoPlay 若在"装载中"翻转, 只靠 autoPlay
    // 变化会错过补播, 装载结束这一刻还需要再看一眼。
  }, [autoPlay, engine.isInitializing]);

  useEffect(() {
    logger('$repeat');
    if (repeat == Repeat.one) {
      player.setPlaylistMode(PlaylistMode.loop);
    } else {
      player.setPlaylistMode(PlaylistMode.none);
    }
    return;
  }, [repeat]);

  useEffect(() {
    if (file?.type != ContentType.video) {
      usePlayerUiStore().updateAspectRatio(0);
      return;
    }

    final width = streams.videoParams?.w ?? 0;
    final height = streams.videoParams?.h ?? 0;
    if (width == 0 || height == 0) {
      usePlayerUiStore().updateAspectRatio(0);
    } else {
      usePlayerUiStore().updateAspectRatio(width / height);
    }
    return;
  }, [file?.type, streams.videoParams?.w, streams.videoParams?.h]);

  Future<void> play() async {
    if (streams.duration == Duration.zero &&
        file != null &&
        !engine.isInitializing) {
      await engine.init(file);
    }
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> seek(Duration newPosition) async =>
      newPosition.inMilliseconds < 0
          ? await player.seek(Duration.zero)
          : newPosition.inMilliseconds > streams.duration.inMilliseconds
              ? await player.seek(streams.duration)
              : await player.seek(newPosition);

  Future<void> backward(int seconds) async {
    await seek(Duration(seconds: streams.position.inSeconds - seconds));
  }

  Future<void> forward(int seconds) async {
    await seek(Duration(seconds: streams.position.inSeconds + seconds));
  }

  Future<void> stepBackward() async {
    final nativePlayer = player.platform;
    if (nativePlayer is NativePlayer && file?.type == ContentType.video) {
      await nativePlayer.command(['frame-back-step']);
      logger('Step backward');
    }
  }

  Future<void> stepForward() async {
    final nativePlayer = player.platform;
    if (nativePlayer is NativePlayer && file?.type == ContentType.video) {
      await nativePlayer.command(['frame-step']);
      logger('Step forward');
    }
  }

  final mediaKitPlayer = useMemoized(
    () => MediaKitPlayer(
      player: player,
      controller: engine.controller,
      audio: streams.audio,
      audios: streams.audios,
      isInitializing: engine.isInitializing,
      isPlaying: streams.playing,
      position: streams.duration == Duration.zero
          ? Duration.zero
          : streams.position,
      duration: streams.duration,
      buffer:
          streams.duration == Duration.zero ? Duration.zero : streams.buffer,
      width: streams.videoParams?.w?.toDouble() ?? 0,
      height: streams.videoParams?.h?.toDouble() ?? 0,
      error: engine.error,
      saveProgress: saveProgress,
      play: play,
      pause: pause,
      backward: backward,
      forward: forward,
      stepBackward: stepBackward,
      stepForward: stepForward,
      seek: seek,
      screenshot: () async {
        try {
          return await player.screenshot(format: 'image/jpeg');
        } catch (e) {
          logger('Error taking screenshot: $e');
          return null;
        }
      },
      // 同步读取缓存值, 由统计 hook 的定时器异步刷新
      getStats: getStats,
    ),
    [
      player,
      engine.controller,
      streams.audio,
      streams.audios,
      engine.isInitializing,
      streams.playing,
      streams.position,
      streams.duration,
      streams.buffer,
      streams.videoParams?.w,
      streams.videoParams?.h,
      engine.error,
      saveProgress,
      play,
      pause,
      backward,
      forward,
      stepBackward,
      stepForward,
      seek,
    ],
  );

  return mediaKitPlayer;
}
