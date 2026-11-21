import 'package:iris/hooks/player/playback_tls.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/hooks/player/playback_load_session.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/wait_for_first_frame.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
    () => Player(configuration: const PlayerConfiguration(libass: false)),
  );
  final controller = useMemoized(() => VideoController(player));
  final session = useMemoized(PlaybackLoadSession.new);
  useListenable(session);

  useEffect(() {
    return () {
      session.dispose();
      unawaited(player.stop().catchError((_) {}));
      unawaited(player.dispose().catchError((_) {}));
    };
  }, const []);

  final playQueue = usePlayQueueStore().select(
    context,
    (state) => state.playQueue,
  );
  final currentIndex = usePlayQueueStore().select(
    context,
    (state) => state.currentIndex,
  );
  final currentPlayIndex = useMemoized(
    () => playQueue.indexWhere((element) => element.index == currentIndex),
    [playQueue, currentIndex],
  );
  final file = currentPlayIndex < 0 ? null : playQueue[currentPlayIndex].file;

  Future<void> init(FileItem file) async {
    if (file.uri.isEmpty) return;
    await session.load(
      errors: player.stream.error,
      ready: () async {
        try {
          await controller.platform.future.timeout(const Duration(seconds: 2));
        } catch (e) {
          logger('Video output not ready: $e');
        }
        await ensurePlaybackTls(player, file.uri);
      },
      open: () async {
        final storage = useStorageStore().findById(file.storageId);
        final auth = storage?.getAuthForUri(file.uri);
        // Always paused: a cancelled native open must never start old audio.
        await player
            .open(
              Media(
                file.uri,
                httpHeaders: auth != null ? {'authorization': auth} : {},
              ),
              play: false,
            )
            .timeout(const Duration(seconds: 15));
      },
      firstFrame: () async {
        if (file.type == ContentType.video) await waitForFirstFrame(controller);
      },
      shouldPlay: () => useAppStore().state.autoPlay,
      play: player.play,
    );
  }

  usePlaybackEntryEffect(
    file: file,
    entryIndex: currentIndex,
    load: () => unawaited(init(file!)),
    stop: () => unawaited(player.stop().catchError((_) {})),
    invalidate: session.invalidate,
  );

  return PlayerEngine(
    player: player,
    controller: controller,
    playQueue: playQueue,
    currentPlayIndex: currentPlayIndex,
    file: file,
    isInitializing: session.initializing,
    error: session.error,
    init: init,
  );
}
