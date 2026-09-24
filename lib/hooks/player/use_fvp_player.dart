import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:fvp/fvp.dart';
import 'package:iris/globals.dart' as globals;
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/check_data_source_type.dart';
import 'package:iris/utils/image_encode.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:media_stream/media_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

FvpPlayer useFvpPlayer(BuildContext context) {
  final autoPlay = useAppStore().select(context, (state) => state.autoPlay);
  final rate = useAppStore().select(context, (state) => state.rate);
  final volume = useAppStore().select(context, (state) => state.volume);
  final isMuted = useAppStore().select(context, (state) => state.isMuted);
  final repeat = useAppStore().select(context, (state) => state.repeat);
  final playQueue =
      usePlayQueueStore().select(context, (state) => state.playQueue);
  final currentIndex =
      usePlayQueueStore().select(context, (state) => state.currentIndex);
  final bool alwaysPlayFromBeginning =
      useAppStore().select(context, (state) => state.alwaysPlayFromBeginning);

  final history = useHistoryStore().select(context, (state) => state.history);

  final looping =
      useMemoized(() => repeat == Repeat.one ? true : false, [repeat]);

  final int currentPlayIndex = useMemoized(
      () => playQueue.indexWhere((element) => element.index == currentIndex),
      [playQueue, currentIndex]);

  final FileItem? file = useMemoized(
      () => playQueue.isEmpty || currentPlayIndex < 0
          ? null
          : playQueue[currentPlayIndex].file,
      [playQueue, currentPlayIndex]);

  final externalSubtitle = useState<int?>(null);

  final List<Subtitle> externalSubtitles =
      useMemoized(() => file?.subtitles ?? [], [file?.subtitles]);

  final isInitializing = useState(false);

  MediaStream mediaStream = useMemoized(() => MediaStream());
  final streamUrl = useMemoized(() => mediaStream.url);

  final controller = useState(VideoPlayerController.networkUrl(Uri.parse('')));

  // 播放统计 (异步刷新, 供 UI 同步读取)
  final fvpStats = useRef<Map<String, String>?>(null);
  final statsTimer = useRef<Timer?>(null);
  final isShowStats =
      usePlayerUiStore().select(context, (state) => state.isShowStats);

  useEffect(() {
    void refreshStats() {
      try {
        final info = controller.value.getMediaInfo();
        if (info == null) return;

        final results = <String, String>{};
        final videos = info.video ?? [];
        if (videos.isNotEmpty) {
          final v = videos.first.codec;
          if (v.codec.isNotEmpty) results['codec'] = v.codec;
          if (v.frameRate > 0) {
            results['fps'] = v.frameRate.toStringAsFixed(2);
          }
          if (v.bitRate > 0) {
            results['bitrate'] =
                '${(v.bitRate / 1000000).toStringAsFixed(2)} Mbps';
          }
          if (v.formatName != null) results['pixfmt'] = v.formatName!;
        }
        final audios = info.audio ?? [];
        if (audios.isNotEmpty) {
          final a = audios.first.codec;
          if (a.codec.isNotEmpty) results['audio'] = a.codec;
          if (a.sampleRate > 0) results['sampleRate'] = '${a.sampleRate} Hz';
        }

        fvpStats.value = results;
      } catch (_) {}
    }

    void start() {
      statsTimer.value?.cancel();
      if (isShowStats) {
        statsTimer.value = Timer.periodic(
          const Duration(seconds: 1),
          (_) => refreshStats(),
        );
        refreshStats();
      }
    }

    start();
    return () {
      statsTimer.value?.cancel();
    };
  }, [isShowStats]);


  final isPlaying = useListenableSelector(
      controller.value, () => controller.value.value.isPlaying);
  final position = useListenableSelector(
      controller.value, () => controller.value.value.position);
  final duration = useListenableSelector(
      controller.value, () => controller.value.value.duration);
  final buffered = useListenableSelector(
      controller.value, () => controller.value.value.buffered);
  final width = useListenableSelector(
      controller.value, () => controller.value.value.size.width);
  final height = useListenableSelector(
      controller.value, () => controller.value.value.size.height);

  useEffect(() {
    if (file?.type != ContentType.video) {
      usePlayerUiStore().updateAspectRatio(0);
      return;
    }

    if (width != 0 && height != 0) {
      usePlayerUiStore().updateAspectRatio(width / height);
    } else {
      usePlayerUiStore().updateAspectRatio(0);
    }
    return;
  }, [file?.type, width, height]);

  Future<void> init(FileItem? file) async {
    isInitializing.value = true;

    try {
      if (controller.value.value.isInitialized) {
        logger('Dispose player');
        controller.value.dispose();
      }

      if (file == null || file.uri.isEmpty) {
        controller.value = VideoPlayerController.networkUrl(Uri.parse(''));
      } else {
        final storage = useStorageStore().findById(file.storageId);
        final auth = storage?.getAuth();

        logger('Open file: $file');

        switch (checkDataSourceType(file)) {
          case DataSourceType.file:
            controller.value = VideoPlayerController.file(
              File(file.uri),
              httpHeaders: auth != null ? {'authorization': auth} : {},
            );
          case DataSourceType.contentUri:
            final isExists = await SafUtil().exists(file.uri, false);
            controller.value = VideoPlayerController.contentUri(
              isExists ? Uri.parse(file.uri) : Uri.parse(''),
            );
          default:
            controller.value = VideoPlayerController.networkUrl(
              Uri.parse(file.storageType == StorageType.ftp
                  ? '$streamUrl/${file.uri}'
                  : file.uri),
              httpHeaders: auth != null ? {'authorization': auth} : {},
            );
        }
      }
      await controller.value.initialize();
      await controller.value.setLooping(repeat == Repeat.one ? true : false);
      await controller.value.setPlaybackSpeed(rate);
      await controller.value.setVolume(isMuted ? 0 : volume / 100);
    } catch (e) {
      logger('Error initializing player: $e');
    } finally {
      isInitializing.value = false;
    }
  }

  useEffect(() {
    init(file);
    return;
  }, [file?.uri]);

  useEffect(() {
    return () {
      if (controller.value.value.isInitialized) {
        controller.value.dispose();
      }
    };
  }, []);

  useEffect(() {
    () async {
      final currentExternalSubtitle = externalSubtitle.value;
      if (currentExternalSubtitle == null || externalSubtitles.isEmpty) {
        controller.value.setExternalSubtitle('');
      } else if (externalSubtitle.value! < externalSubtitles.length) {
        bool isExists = true;

        final uri = file?.storageType == StorageType.ftp
            ? '$streamUrl/${externalSubtitles[currentExternalSubtitle].uri}'
            : externalSubtitles[currentExternalSubtitle].uri;

        logger('External subtitle uri: $uri');

        if (Platform.isAndroid &&
            externalSubtitles[currentExternalSubtitle]
                .uri
                .startsWith('content://')) {
          isExists = await SafUtil().exists(uri, false);
        }

        if (isExists) {
          controller.value.setExternalSubtitle(uri);
        } else {
          externalSubtitle.value = null;
        }
      }
    }();

    return;
  }, [externalSubtitles, externalSubtitle.value]);

  useEffect(() {
    () async {
      if (file != null &&
          controller.value.value.isCompleted &&
          controller.value.value.position != Duration.zero &&
          controller.value.value.duration != Duration.zero) {
        logger('Completed: ${file.name}');
        if (repeat == Repeat.one) return;
        if (currentPlayIndex == playQueue.length - 1) {
          if (repeat == Repeat.all) {
            await usePlayQueueStore().updateCurrentIndex(playQueue[0].index);
          }
        } else {
          await usePlayQueueStore()
              .updateCurrentIndex(playQueue[currentPlayIndex + 1].index);
        }
      }
    }();
    return;
  }, [controller.value.value.isCompleted]);

  useEffect(() {
    if (controller.value.value.isInitialized) {
      controller.value.setPlaybackSpeed(rate);
    }
    return;
  }, [rate]);

  useEffect(() {
    if (controller.value.value.isInitialized) {
      controller.value.setVolume(isMuted ? 0 : volume / 100);
    }
    return;
  }, [volume, isMuted]);

  useEffect(() {
    if (controller.value.value.isInitialized) {
      logger('Set looping: $looping');
      controller.value.setLooping(repeat == Repeat.one ? true : false);
    }
    return;
  }, [looping]);

  useEffect(() {
    () async {
      if (controller.value.value.duration != Duration.zero &&
          file != null &&
          file.type == ContentType.video) {
        Progress? progress = history[file.getID()];
        if (progress != null) {
          if (!alwaysPlayFromBeginning &&
              (progress.duration.inMilliseconds -
                      progress.position.inMilliseconds) >
                  5000) {
            logger(
                'Resume progress: ${file.name} position: ${progress.position} duration: ${progress.duration}');
            await controller.value.seekTo(progress.position);
          }
        }
      }

      if (autoPlay) {
        controller.value.play();
      }

      if (externalSubtitles.isNotEmpty) {
        externalSubtitle.value = 0;
      }
    }();
    return;
  }, [controller.value.value.duration]);

  useEffect(() {
    return () {
      if (isAndroid &&
          globals.initUri == file?.uri &&
          globals.initUri != null &&
          globals.initUri!.startsWith('content://')) {
        return;
      }

      if (file != null &&
          controller.value.value.isInitialized &&
          controller.value.value.duration.inSeconds != 0) {
        logger(
            'Save progress: ${file.name}, position: ${controller.value.value.position}, duration: ${controller.value.value.duration}');
        useHistoryStore().add(Progress(
          dateTime: DateTime.now().toUtc(),
          position: controller.value.value.position,
          duration: controller.value.value.duration,
          file: file,
        ));
      }
    };
  }, [file]);

  useEffect(() {
    if (controller.value.value.isPlaying) {
      logger('Enable wakelock');
      WakelockPlus.enable();
    } else {
      logger('Disable wakelock');
      WakelockPlus.disable();
    }
    return;
  }, [controller.value.value.isPlaying]);

  Future<void> play() async {
    if (!controller.value.value.isInitialized &&
        !isInitializing.value &&
        file != null) {
      init(file);
    }
    controller.value.play();
  }

  Future<void> pause() async {
    controller.value.pause();
  }

  Future<void> seek(Duration newPosition) async {
    logger('Seek to: $newPosition');
    if (controller.value.value.duration == Duration.zero) return;
    newPosition.inSeconds < 0
        ? await controller.value.seekTo(Duration.zero)
        : newPosition.inSeconds > controller.value.value.duration.inSeconds
            ? await controller.value.seekTo(controller.value.value.duration)
            : await controller.value.seekTo(newPosition);
  }

  Future<void> backward(int seconds) async => await seek(
      Duration(seconds: controller.value.value.position.inSeconds - seconds));

  Future<void> forward(int seconds) async => await seek(
      Duration(seconds: controller.value.value.position.inSeconds + seconds));

  Future<void> stepBackward() async {
    if (file?.type == ContentType.video) {
      await controller.value.step(frames: -1);
      logger('Step backward');
    }
  }

  Future<void> stepForward() async {
    if (file?.type == ContentType.video) {
      await controller.value.step(frames: 1);
      logger('Step forward');
    }
  }

  Future<void> saveProgress() async {
    if (isAndroid &&
        globals.initUri == file?.uri &&
        globals.initUri != null &&
        globals.initUri!.startsWith('content://')) {
      return;
    }

    if (file != null && controller.value.value.duration != Duration.zero) {
      logger(
          'Save progress: ${file.name}, position: ${controller.value.value.position}, duration: ${controller.value.value.duration}');
      useHistoryStore().add(Progress(
        dateTime: DateTime.now().toUtc(),
        position: controller.value.value.position,
        duration: controller.value.value.duration,
        file: file,
      ));
    }
  }

  useEffect(() => saveProgress, []);

  final fvpPlayer = useMemoized(
    () => FvpPlayer(
      controller: controller.value,
      isInitializing: isInitializing.value,
      isPlaying: isPlaying,
      externalSubtitle: externalSubtitle,
      externalSubtitles: externalSubtitles,
      position:
          !controller.value.value.isInitialized || duration == Duration.zero
              ? Duration.zero
              : position,
      duration: controller.value.value.isInitialized ? duration : Duration.zero,
      buffer: buffered.isEmpty || duration == Duration.zero
          ? Duration.zero
          : buffered.reduce((max, curr) => curr.end > max.end ? curr : max).end,
      width: width,
      height: height,
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
          // FVP snapshot 返回 RGBA 原始数据, 需要编码为图片
          final raw = await controller.value.snapshot();
          if (raw == null) return null;
          return await encodeRgbaToPng(
            raw,
            width: controller.value.value.size.width.toInt(),
            height: controller.value.value.size.height.toInt(),
          );
        } catch (e) {
          logger('Error taking screenshot: $e');
          return null;
        }
      },
      getStats: () => fvpStats.value ?? const {},
    ),
    [
      controller.value,
      controller.value.value.isInitialized,
      isInitializing.value,
      isPlaying,
      externalSubtitle.value,
      externalSubtitles,
      position,
      duration,
      buffered,
      width,
      height,
      play,
      pause,
      seek,
      backward,
      forward,
      stepBackward,
      stepForward,
      saveProgress,
    ],
  );

  return fvpPlayer;
}
