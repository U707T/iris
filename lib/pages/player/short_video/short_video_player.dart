import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/short_video.dart';
import 'package:media_kit/media_kit.dart';

/// 短视频模式的播放器适配层。
///
/// 池本身 (`short_video_pool.dart`) 只负责槽位调度 / 预载 / 进度,
/// 这里负责把"当前槽位"包装成界面使用的 [MediaPlayer]：
/// 播放控制、seek、截图, 以及把池的当前槽位状态映射成 UI 快照。

/// 时长取值: 优先非零值 (流事件可能缺失, 此时以同步状态兜底)
Duration _preferNonZero(Duration? preferred, Duration fallback) {
  if (preferred != null && preferred > Duration.zero) return preferred;
  if (fallback > Duration.zero) return fallback;
  return preferred ?? fallback;
}

/// 短视频模式专用的 MediaPlayer, 附带播放器池供预载页面显示画面
class ShortVideoMediaKitPlayer extends MediaKitPlayer {
  final ShortVideoPool pool;

  ShortVideoMediaKitPlayer({
    required this.pool,
    required super.player,
    required super.controller,
    required super.audio,
    required super.audios,
    required super.isInitializing,
    required super.isPlaying,
    required super.position,
    required super.duration,
    required super.buffer,
    required super.width,
    required super.height,
    super.error,
    required super.saveProgress,
    required super.play,
    required super.pause,
    required super.backward,
    required super.forward,
    required super.stepBackward,
    required super.stepForward,
    required super.seek,
    super.screenshot,
    super.getStats,
  });
}

/// 短视频模式的 Media Kit 播放器池宿主
MediaPlayer useShortVideoMediaKitPlayer(BuildContext context) {
  final playQueue =
      usePlayQueueStore().select(context, (state) => state.playQueue);
  final currentIndex =
      usePlayQueueStore().select(context, (state) => state.currentIndex);

  final items = useMemoized(() => getVideoItems(playQueue), [playQueue]);
  final currentFeedIndex = useMemoized(
    () => items.indexWhere((item) => item.index == currentIndex),
    [items, currentIndex],
  );


  final pool = useMemoized(
    () => ShortVideoPool(
      buildMedia: (file) {
        final storage = useStorageStore().findById(file.storageId);
        final auth = storage?.getAuth();
        return Media(
          file.uri,
          httpHeaders: auth != null ? {'authorization': auth} : {},
        );
      },
    ),
  );

  useEffect(() {
    return () => pool.dispose();
  }, [pool]);

  // 槽位装载完成 / 失败时刷新界面
  useListenable(pool);

  pool.reconcile(currentFeedIndex, items);

  final rate = useAppStore().select(context, (state) => state.rate);
  final volume = useAppStore().select(context, (state) => state.volume);
  final isMuted = useAppStore().select(context, (state) => state.isMuted);

  useEffect(() {
    for (final slot in pool.slots) {
      if (slot.loadedFile != null) slot.player.setRate(rate);
    }
    return;
  }, [rate]);

  useEffect(() {
    for (final slot in pool.slots) {
      if (slot.loadedFile != null) {
        slot.player.setVolume(isMuted ? 0 : volume.toDouble());
      }
    }
    return;
  }, [volume, isMuted]);

  final active =
      pool.slotFor(currentFeedIndex) ?? pool.activeSlot ?? pool.slots.first;
  final activePlayer = active.player;

  // 注意: media_kit 的流不重放历史事件, 订阅开始前发生的事件会错过
  // (预载槽位在激活前就已经打开完毕), 因此用同步的 state 做兜底。
  final playing = useStream(
        activePlayer.stream.playing,
        preserveState: false,
      ).data ??
      activePlayer.state.playing;
  final position = useStream(
        activePlayer.stream.position,
        preserveState: false,
      ).data ??
      activePlayer.state.position;
  final duration = _preferNonZero(
    useStream(activePlayer.stream.duration, preserveState: false).data,
    activePlayer.state.duration,
  );
  final videoParams = useStream(
        activePlayer.stream.videoParams,
        preserveState: false,
      ).data ??
      activePlayer.state.videoParams;

  Future<void> play() async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    // 装载失败后点播放 = 重试: 重新 open 一次, 而不是对着空播放器 play()
    if (slot.error != null) {
      pool.reopen(slot);
      return;
    }
    pool.userPaused = false;
    // 播放器可能正在销毁 (模式刚退出), 失败时忽略
    try {
      await slot.player.play();
      slot.played = true;
    } catch (e) {
      logger('Short video play error: $e');
    }
  }

  Future<void> pause() async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    pool.userPaused = true;
    try {
      await slot.player.pause();
    } catch (e) {
      logger('Short video pause error: $e');
    }
  }

  Future<void> seek(Duration newPosition) async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    final liveDuration = _preferNonZero(duration, slot.player.state.duration);
    try {
      newPosition.inMilliseconds < 0
          ? await slot.player.seek(Duration.zero)
          : liveDuration > Duration.zero && newPosition > liveDuration
              ? await slot.player.seek(liveDuration)
              : await slot.player.seek(newPosition);
    } catch (e) {
      logger('Short video seek error: $e');
    }
  }

  Future<void> backward(int seconds) async =>
      await seek(Duration(seconds: position.inSeconds - seconds));

  Future<void> forward(int seconds) async =>
      await seek(Duration(seconds: position.inSeconds + seconds));

  Future<void> stepBackward() async {
    final nativePlayer = pool.slotFor(pool.currentFeedIndex)?.player.platform;
    if (nativePlayer is NativePlayer) {
      try {
        await nativePlayer.command(['frame-back-step']);
      } catch (e) {
        logger('Short video step backward error: $e');
      }
    }
  }

  Future<void> stepForward() async {
    final nativePlayer = pool.slotFor(pool.currentFeedIndex)?.player.platform;
    if (nativePlayer is NativePlayer) {
      try {
        await nativePlayer.command(['frame-step']);
      } catch (e) {
        logger('Short video step forward error: $e');
      }
    }
  }

  Future<void> saveProgress() async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot != null && slot.played) pool.saveSlotProgress(slot);
  }

  return ShortVideoMediaKitPlayer(
    pool: pool,
    player: activePlayer,
    controller: active.controller,
    audio: AudioTrack.no(),
    audios: const [],
    isInitializing: active.initializing,
    isPlaying: playing,
    position: duration == Duration.zero ? Duration.zero : position,
    duration: duration,
    buffer: Duration.zero,
    width: videoParams.w?.toDouble() ?? 0,
    height: videoParams.h?.toDouble() ?? 0,
    error: active.error,
    play: play,
    pause: pause,
    backward: backward,
    forward: forward,
    stepBackward: stepBackward,
    stepForward: stepForward,
    seek: seek,
    saveProgress: saveProgress,
    screenshot: () async {
      try {
        return await activePlayer.screenshot(
          format: 'image/jpeg',
        );
      } catch (e) {
        logger('Error taking screenshot: $e');
        return null;
      }
    },
    getStats: () => const {},
  );
}
