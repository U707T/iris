import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/playback_load_session.dart';
import 'package:iris/hooks/player/use_player_progress.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';
import 'package:iris/models/store/history_state.dart';
import 'package:iris/store/persistence/json_persistence.dart';
import 'package:iris/store/persistence/key_value_store.dart';
import 'package:iris/store/use_history_store.dart';
import 'package:media_kit/media_kit.dart';
// ignore: depend_on_referenced_packages
import 'package:zustand/zustand.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _State extends Fake implements PlayerState {
  @override
  Duration duration = Duration.zero;
  @override
  Duration position = Duration.zero;
}

class _Player extends Fake implements Player {
  final backendState = _State();
  final trace = <String>[];
  final nextOpen = Completer<void>();
  String media = 'none';

  @override
  PlayerState get state => backendState;

  Future<void> openEntry(FileItem file) async {
    trace.add('open-start:${file.name}');
    if (file.name == 'b') await nextOpen.future;
    media = file.name;
    backendState.duration = const Duration(minutes: 2);
    backendState.position = Duration.zero;
    trace.add('open-done:${file.name}');
  }

  @override
  Future<void> seek(Duration position) async {
    trace.add('seek:$media:${position.inSeconds}');
    backendState.position = position;
  }
}

void main() {
  testWidgets('navigation restores the new entry only after its slow open', (
    tester,
  ) async {
    const files = [
      FileItem(name: 'a', uri: '/a.mp4'),
      FileItem(name: 'b', uri: '/b.mp4'),
      FileItem(name: 'c', uri: '/c.mp4'),
    ];
    final historyStore = HistoryStore(
      persistence: JsonPersistence<HistoryState>(
        store: _MemoryStore(),
        key: 'history',
        fromJson: HistoryState.fromJson,
        toJson: (state) => state.toJson(),
      ),
    );
    StoreLocator().put(HistoryStore, historyStore);
    await tester.pump();
    await historyStore.ready;
    final initialHistoryWrite = historyStore.add(
      Progress(
        dateTime: DateTime.utc(2026),
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 2),
        file: files[1],
      ),
    );
    await tester.pump();
    await initialHistoryWrite;
    final player = _Player();
    final entry = ValueNotifier(0);
    final session = PlaybackLoadSession();
    final errors = StreamController<String>.broadcast();
    Future<void> Function()? saveCurrentProgress;
    addTearDown(() async {
      if (!player.nextOpen.isCompleted) player.nextOpen.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.idle();
      final cleanup = () async {
        session.dispose();
        entry.dispose();
        await errors.close();
        final locator = StoreLocator();
        await locator.delete(HistoryStore);
        await locator.dispose();
      }();
      await tester.pump();
      await tester.idle();
      await cleanup;
    });

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: entry,
        builder: (_, index, _) => HookBuilder(
          builder: (_) {
            useListenable(session);
            final file = files[index];
            usePlaybackEntryEffect(
              file: file,
              entryIndex: index,
              load: () => unawaited(
                session.load(
                  identity: (file, index),
                  errors: errors.stream,
                  ready: () async {},
                  open: () => player.openEntry(file),
                  firstFrame: () async {},
                  play: () async {},
                  shouldPlay: () => false,
                ),
              ),
              stop: () {},
              invalidate: session.invalidate,
            );
            final history =
                useStream(historyStore.stream).data ?? historyStore.state;
            saveCurrentProgress = usePlayerProgress(
              player: player,
              file: file,
              entryIndex: index,
              ownsCurrentMedia: () => session.loadedIdentity == (file, index),
              isReady:
                  session.loadedIdentity == (file, index) &&
                  !session.initializing &&
                  session.error == null,
              duration: player.state.duration,
              alwaysPlayFromBeginning: false,
              history: history.history,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(player.media, 'a');
    player.backendState.position = const Duration(seconds: 10);

    entry.value = 1;
    await tester.pump();
    await tester.pump();
    expect(player.trace, contains('open-start:b'));
    expect(
      historyStore.findById(files[0].getID())?.position,
      const Duration(seconds: 10),
      reason: 'A must still save its own progress when leaving',
    );
    expect(
      historyStore.findById(files[1].getID())?.position,
      const Duration(seconds: 30),
    );
    final pendingBSave = saveCurrentProgress!;
    final savingWhileOpening = pendingBSave();
    await tester.pump();
    await savingWhileOpening;
    expect(player.media, 'a');
    expect(
      historyStore.findById(files[1].getID())?.position,
      const Duration(seconds: 30),
      reason: 'saving pending B must not overwrite its history with A state',
    );
    // The old entry's cleanup saves history and causes another build while B
    // is still opening. Its duration is not proof B has loaded yet.
    expect(
      player.trace.where((event) => event.startsWith('seek:')),
      isEmpty,
      reason: 'B history must not seek the still-loaded A',
    );

    // Leaving an entry that has never owned the backend must also leave its
    // history untouched; this exercises B's cleanup rather than an explicit save.
    entry.value = 2;
    await tester.pump();
    await tester.pump();
    expect(player.media, 'c');
    expect(
      historyStore.findById(files[1].getID())?.position,
      const Duration(seconds: 30),
      reason: 'skipping pending B must not save A state under B',
    );
    entry.value = 1;
    await tester.pump();
    await tester.pump();
    expect(player.media, 'c');
    expect(
      historyStore.findById(files[1].getID())?.position,
      const Duration(seconds: 30),
    );
    player.nextOpen.complete();
    await tester.pump();
    await tester.pump();
    expect(player.trace, contains('seek:b:30'));
    expect(player.state.position, const Duration(seconds: 30));
    player.backendState.position = const Duration(seconds: 45);
    // Reuse the callback captured while B was still loading: readiness must be
    // checked dynamically instead of freezing its initial false value.
    final savingLoadedB = pendingBSave();
    await tester.pump();
    await savingLoadedB;
    expect(
      historyStore.findById(files[1].getID())?.position,
      const Duration(seconds: 45),
      reason: 'B must save after loading despite being initially not ready',
    );
    expect(
      historyStore.findById(files[0].getID())?.position,
      const Duration(seconds: 10),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.idle();
  });

  testWidgets('equal files in different entries each restore only once', (
    tester,
  ) async {
    const file = FileItem(name: 'same', uri: '/same.mp4');
    final historyStore = HistoryStore(
      persistence: JsonPersistence<HistoryState>(
        store: _MemoryStore(),
        key: 'history',
        fromJson: HistoryState.fromJson,
        toJson: (state) => state.toJson(),
      ),
    );
    StoreLocator().put(HistoryStore, historyStore);
    await tester.pump();
    await historyStore.ready;
    Progress progressAt(int seconds) => Progress(
      dateTime: DateTime.utc(2026),
      position: Duration(seconds: seconds),
      duration: const Duration(minutes: 2),
      file: file,
    );
    final initialHistoryWrite = historyStore.add(progressAt(30));
    await tester.pump();
    await initialHistoryWrite;
    final player = _Player();
    final entry = ValueNotifier(0);
    final session = PlaybackLoadSession();
    final errors = StreamController<String>.broadcast();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.idle();
      final cleanup = () async {
        session.dispose();
        entry.dispose();
        await errors.close();
        final locator = StoreLocator();
        await locator.delete(HistoryStore);
        await locator.dispose();
      }();
      await tester.pump();
      await tester.idle();
      await cleanup;
    });

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: entry,
        builder: (_, index, _) => HookBuilder(
          builder: (_) {
            useListenable(session);
            usePlaybackEntryEffect(
              file: file,
              entryIndex: index,
              load: () => unawaited(
                session.load(
                  identity: (file, index),
                  errors: errors.stream,
                  ready: () async {},
                  open: () => player.openEntry(file),
                  firstFrame: () async {},
                  play: () async {},
                  shouldPlay: () => false,
                ),
              ),
              stop: () {},
              invalidate: session.invalidate,
            );
            final history =
                useStream(historyStore.stream).data ?? historyStore.state;
            usePlayerProgress(
              player: player,
              file: file,
              entryIndex: index,
              ownsCurrentMedia: () => session.loadedIdentity == (file, index),
              isReady:
                  session.loadedIdentity == (file, index) &&
                  !session.initializing &&
                  session.error == null,
              duration: player.state.duration,
              alwaysPlayFromBeginning: false,
              history: history.history,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(player.trace.where((event) => event.startsWith('seek:')), [
      'seek:same:30',
    ]);

    player.backendState.position = const Duration(seconds: 45);
    final firstHistoryWrite = historyStore.add(progressAt(70));
    await tester.pump();
    await firstHistoryWrite;
    expect(
      player.state.position,
      const Duration(seconds: 45),
      reason: 'history writes must not resume an already restored entry',
    );

    entry.value = 1;
    await tester.pump();
    await tester.pump();
    expect(
      player.trace.where((event) => event == 'open-done:same'),
      hasLength(2),
    );
    expect(player.trace.where((event) => event.startsWith('seek:')), [
      'seek:same:30',
      'seek:same:45',
    ]);
    expect(player.state.position, const Duration(seconds: 45));

    player.backendState.position = const Duration(seconds: 50);
    final secondHistoryWrite = historyStore.add(progressAt(80));
    await tester.pump();
    await secondHistoryWrite;
    expect(player.state.position, const Duration(seconds: 50));
    expect(
      player.trace.where((event) => event.startsWith('seek:')),
      hasLength(2),
    );
  });
}
