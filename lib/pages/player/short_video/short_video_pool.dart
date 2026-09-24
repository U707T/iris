import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/short_video.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_stream/media_stream.dart';

/// 播放器池大小: 上一条 / 当前 / 下一条
const int _shortVideoPoolSize = 3;

/// 单个播放器槽位
class ShortVideoSlot {
  ShortVideoSlot({required this.player, required this.controller});

  final Player player;
  final VideoController controller;

  /// 承载的信息流下标 (null = 空闲)
  int? feedIndex;

  /// 对应文件 (用于保存进度)
  FileItem? loadedFile;

  /// 是否正在装载
  bool initializing = false;

  /// 是否真正播放过 (未播放过的预载槽位不需要保存进度)
  bool played = false;

  /// 装载序号, 用于丢弃过期的异步结果
  int token = 0;

  /// 是否有等待执行的装载请求
  bool pendingOpen = false;
}

/// 短视频模式使用的预载播放器池:
/// 同时保持 3 个播放器实例 (上一条 / 当前 / 下一条),
/// 滑动切换时直接复用已装载的实例, 实现无缝切换。
class ShortVideoPool extends ChangeNotifier {
  ShortVideoPool({required this.buildMedia}) {
    for (var i = 0; i < _shortVideoPoolSize; i++) {
      final player = Player();
      slots.add(
        ShortVideoSlot(player: player, controller: VideoController(player)),
      );
    }
  }

  final Media Function(FileItem file) buildMedia;
  final List<ShortVideoSlot> slots = [];

  List<PlayQueueItem> items = const [];
  int currentFeedIndex = 0;

  /// 用户是否主动暂停了当前视频 (划到新视频时重置)
  bool userPaused = false;

  ShortVideoSlot? _active;
  bool _ensureActivePending = false;
  bool _applyScheduled = false;
  bool disposed = false;

  /// 待保存的进度 (在 build 中收集, 帧后执行)
  final List<({FileItem file, Duration position, Duration duration})>
      _pendingSaves = [];

  ShortVideoSlot? slotFor(int feedIndex) {
    for (final slot in slots) {
      if (slot.feedIndex == feedIndex) return slot;
    }
    return null;
  }

  /// 根据当前下标决定各槽位的装载目标 (在 build 中调用)
  void reconcile(int current, List<PlayQueueItem> items) {
    if (disposed) return;

    // 队列变化时校验槽位承载的文件是否仍然匹配
    if (!identical(items, this.items)) {
      for (final slot in slots) {
        final index = slot.feedIndex;
        if (index == null) continue;
        if (index >= items.length || items[index].file != slot.loadedFile) {
          final state = slot.player.state;
          if (slot.played &&
              slot.loadedFile != null &&
              state.duration != Duration.zero) {
            _pendingSaves.add((
              file: slot.loadedFile!,
              position: state.position,
              duration: state.duration,
            ));
          }
          slot.pendingOpen = false;
          slot.played = false;
          slot.feedIndex = null;
        }
      }
    }

    this.items = items;
    currentFeedIndex = current;

    if (items.isEmpty || current < 0 || current >= items.length) {
      _maybeSchedule();
      return;
    }

    // 需要就绪的下标: 当前 / 下一条 / 上一条
    final needed = <int>{};
    for (final offset in const [0, 1, -1]) {
      final index = current + offset;
      if (index >= 0 && index < items.length) needed.add(index);
    }

    // 为缺失的下标分配槽位 (当前视频优先)
    for (final offset in const [0, 1, -1]) {
      final want = current + offset;
      if (want < 0 || want >= items.length) continue;
      if (slotFor(want) != null) continue;

      final slot = _pickReusable(needed);
      if (slot == null) continue;

      // 复用前捕获旧视频的播放进度
      final state = slot.player.state;
      if (slot.played &&
          slot.loadedFile != null &&
          state.duration != Duration.zero) {
        _pendingSaves.add((
          file: slot.loadedFile!,
          position: state.position,
          duration: state.duration,
        ));
      }

      slot.feedIndex = want;
      slot.loadedFile = items[want].file;
      slot.initializing = true;
      slot.played = false;
      slot.pendingOpen = true;
    }

    // 激活当前下标所在槽位
    final newActive = slotFor(current);
    if (newActive != null && newActive != _active) {
      _active = newActive;
      _ensureActivePending = true;
      userPaused = false;
    }

    _maybeSchedule();
  }

  void _maybeSchedule() {
    if (_applyScheduled || disposed) return;
    if (!_ensureActivePending &&
        _pendingSaves.isEmpty &&
        !slots.any((slot) => slot.pendingOpen)) {
      return;
    }
    _applyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyScheduled = false;
      applyPending();
    });
  }

  /// 执行 reconcile 记录的装载 / 播放动作 (帧后调用)
  void applyPending() {
    if (disposed) return;

    // 保存队列变化时收集的进度
    if (_pendingSaves.isNotEmpty) {
      for (final save in _pendingSaves) {
        useHistoryStore().add(Progress(
          dateTime: DateTime.now().toUtc(),
          position: save.position,
          duration: save.duration,
          file: save.file,
        ));
      }
      _pendingSaves.clear();
    }

    // 打开待装载的槽位, 当前视频优先
    final pending = slots.where((slot) => slot.pendingOpen).toList()
      ..sort((a, b) => (a.feedIndex == currentFeedIndex ? 0 : 1)
          .compareTo(b.feedIndex == currentFeedIndex ? 0 : 1));
    for (final slot in pending) {
      slot.pendingOpen = false;
      unawaited(_openSlot(slot));
    }

    final active = slotFor(currentFeedIndex);

    // 活动槽位已就绪则立即开始播放 (用户主动暂停过则跳过)
    if (_ensureActivePending) {
      _ensureActivePending = false;
      if (active != null && !active.initializing && !userPaused) {
        unawaited(active.player.play());
        active.played = true;
      }
    }

    // 暂停其它槽位, 避免上一个视频继续出声
    if (active != null) {
      for (final slot in slots) {
        if (slot != active && slot.player.state.playing) {
          unawaited(slot.player.pause());
        }
      }
    }
  }

  ShortVideoSlot? _pickReusable(Set<int> needed) {
    // 优先空闲槽位
    for (final slot in slots) {
      if (slot.feedIndex == null) return slot;
    }
    // 其次复用非活动且不再需要的槽位
    for (final slot in slots) {
      if (slot != _active && !needed.contains(slot.feedIndex)) return slot;
    }
    for (final slot in slots) {
      if (!needed.contains(slot.feedIndex)) return slot;
    }
    return null;
  }

  Future<void> _openSlot(ShortVideoSlot slot) async {
    final file = slot.loadedFile;
    if (file == null) return;

    final token = ++slot.token;
    try {
      await slot.player.open(buildMedia(file), play: false);
      if (disposed || token != slot.token) return;

      await slot.player.setPlaylistMode(PlaylistMode.loop);

      final appState = useAppStore().state;
      await slot.player.setRate(appState.rate);
      await slot.player.setVolume(
          appState.isMuted ? 0 : appState.volume.toDouble());

      if (disposed || token != slot.token) return;
      slot.initializing = false;
      notifyListeners();

      // 已成为当前视频则立即开始播放 (用户主动暂停过则跳过)
      if (!userPaused && slotFor(currentFeedIndex) == slot) {
        unawaited(slot.player.play());
        slot.played = true;
      }
    } catch (e) {
      logger('Short video pool open error: $e');
      if (!disposed && token == slot.token) {
        slot.initializing = false;
        notifyListeners();
      }
    }
  }

  /// 保存某个槽位的播放进度
  void saveSlotProgress(ShortVideoSlot slot) {
    final file = slot.loadedFile;
    if (file == null) return;

    final state = slot.player.state;
    if (state.duration == Duration.zero) return;

    useHistoryStore().add(Progress(
      dateTime: DateTime.now().toUtc(),
      position: state.position,
      duration: state.duration,
      file: file,
    ));
  }

  @override
  void dispose() {
    disposed = true;
    for (final slot in slots) {
      if (slot.played) saveSlotProgress(slot);
      slot.player.dispose();
    }
    super.dispose();
  }
}

/// 短视频模式专用的 MediaPlayer, 附带播放器池供预载页面显示画面
class ShortVideoMediaKitPlayer extends MediaKitPlayer {
  final ShortVideoPool pool;

  ShortVideoMediaKitPlayer({
    required this.pool,
    required super.player,
    required super.controller,
    required super.subtitle,
    required super.subtitles,
    required super.externalSubtitles,
    required super.audio,
    required super.audios,
    required super.isInitializing,
    required super.isPlaying,
    required super.position,
    required super.duration,
    required super.buffer,
    required super.width,
    required super.height,
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

  final mediaStream = useMemoized(() => MediaStream(), []);

  final pool = useMemoized(
    () => ShortVideoPool(
      buildMedia: (file) {
        final storage = useStorageStore().findById(file.storageId);
        final auth = storage?.getAuth();
        return Media(
          file.storageType == StorageType.ftp
              ? '${mediaStream.url}/${file.uri}'
              : file.uri,
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

  final active = pool.slotFor(currentFeedIndex) ?? pool.slots.first;
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
  final duration = useStream(
        activePlayer.stream.duration,
        preserveState: false,
      ).data ??
      activePlayer.state.duration;
  final videoParams = useStream(
        activePlayer.stream.videoParams,
        preserveState: false,
      ).data ??
      activePlayer.state.videoParams;

  Future<void> play() async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    pool.userPaused = false;
    await slot.player.play();
    slot.played = true;
  }

  Future<void> pause() async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    pool.userPaused = true;
    await slot.player.pause();
  }

  Future<void> seek(Duration newPosition) async {
    final slot = pool.slotFor(pool.currentFeedIndex);
    if (slot == null) return;
    newPosition.inMilliseconds < 0
        ? await slot.player.seek(Duration.zero)
        : newPosition.inMilliseconds > duration.inMilliseconds
            ? await slot.player.seek(duration)
            : await slot.player.seek(newPosition);
  }

  Future<void> backward(int seconds) async =>
      await seek(Duration(seconds: position.inSeconds - seconds));

  Future<void> forward(int seconds) async =>
      await seek(Duration(seconds: position.inSeconds + seconds));

  Future<void> stepBackward() async {
    final nativePlayer = pool.slotFor(pool.currentFeedIndex)?.player.platform;
    if (nativePlayer is NativePlayer) {
      await nativePlayer.command(['frame-back-step']);
    }
  }

  Future<void> stepForward() async {
    final nativePlayer = pool.slotFor(pool.currentFeedIndex)?.player.platform;
    if (nativePlayer is NativePlayer) {
      await nativePlayer.command(['frame-step']);
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
    subtitle: SubtitleTrack.no(),
    subtitles: const [],
    externalSubtitles: const [],
    audio: AudioTrack.no(),
    audios: const [],
    isInitializing: active.initializing,
    isPlaying: playing,
    position: duration == Duration.zero ? Duration.zero : position,
    duration: duration,
    buffer: Duration.zero,
    width: videoParams.w?.toDouble() ?? 0,
    height: videoParams.h?.toDouble() ?? 0,
    play: play,
    pause: pause,
    backward: backward,
    forward: forward,
    stepBackward: stepBackward,
    stepForward: stepForward,
    seek: seek,
    saveProgress: saveProgress,
    screenshot: ({bool includeSubtitles = false}) async {
      try {
        return await activePlayer.screenshot(
          format: 'image/jpeg',
          includeLibassSubtitles: includeSubtitles,
        );
      } catch (e) {
        logger('Error taking screenshot: $e');
        return null;
      }
    },
    getStats: () => const {},
  );
}
