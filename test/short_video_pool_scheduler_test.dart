import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/player/short_video/short_video_player.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _State implements PlayerState {
  @override
  bool playing = false;
  @override
  Duration get duration => const Duration(minutes: 1);
  @override
  Duration get position => const Duration(seconds: 15);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Streams implements PlayerStream {
  _Streams(this.errors);
  final Stream<String> errors;
  @override
  Stream<String> get error => errors;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  final errors = StreamController<String>.broadcast(sync: true);
  final _state = _State();
  int plays = 0;
  int stops = 0;
  Future<void> Function()? onStop;
  @override
  PlayerState get state => _state;
  @override
  PlayerStream get stream => _Streams(errors.stream);
  @override
  Future<void> play() async {
    plays++;
    _state.playing = true;
  }

  @override
  Future<void> pause() async {
    _state.playing = false;
  }

  @override
  Future<void> stop() async {
    stops++;
    await onStop?.call();
    _state.playing = false;
  }

  @override
  Future<void> dispose() => errors.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Video implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<PlayQueueItem> _items(int count, {String prefix = 'v'}) => [
  for (var i = 0; i < count; i++)
    PlayQueueItem(
      index: i,
      file: FileItem(
        name: '$prefix$i',
        uri: '/$prefix$i.mp4',
        type: ContentType.video,
      ),
    ),
];

List<ShortVideoSlot> _slots([int count = 3]) => [
  for (var i = 0; i < count; i++)
    ShortVideoSlot(player: _Player(), controller: _Video()),
];

void main() {
  testWidgets('current load completion precedes serial adjacent preloads', (
    tester,
  ) async {
    final gates = List.generate(3, (_) => Completer<void>());
    final opens = <int>[];
    final slots = _slots();
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: slots,
      writeProgress: (_) async {},
      loadSlot: (slot, file) {
        final index = int.parse(file.name.substring(1));
        opens.add(index);
        return gates[index].future;
      },
    );
    pool.reconcile(1, _items(3));
    pool.applyPending();
    await tester.pump();
    expect(opens, [1]);
    gates[1].complete();
    await tester.pump();
    expect(opens, [1, 2]);
    await tester.pump();
    expect(opens, [1, 2], reason: 'only one speculative open may be in flight');
    gates[2].complete();
    await tester.pump();
    expect(opens, [1, 2, 0]);
    gates[0].complete();
    await tester.pump();
    expect((pool.slotFor(1)!.player as _Player).plays, 1);
    expect((pool.slotFor(2)!.player as _Player).plays, 0);
    expect((pool.slotFor(0)!.player as _Player).plays, 0);
    pool.dispose();
    await tester.pump();
  });

  testWidgets(
    'a busy slot opens only the newest replacement and never overlaps',
    (tester) async {
      final old = Completer<void>();
      final latest = Completer<void>();
      final opens = <String>[];
      var inFlight = 0;
      var maxInFlight = 0;
      final slot = _slots(1).single;
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: [slot],
        writeProgress: (_) async {},
        loadSlot: (_, file) async {
          opens.add(file.name);
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await (file.name == 'a0' ? old.future : latest.future);
          inFlight--;
        },
      );
      pool.reconcile(0, _items(1, prefix: 'a'));
      pool.applyPending();
      pool.reconcile(0, _items(1, prefix: 'b'));
      pool.applyPending();
      pool.reconcile(0, _items(1, prefix: 'c'));
      pool.applyPending();
      expect(opens, ['a0']);
      old.complete();
      await tester.pump();
      expect(opens, ['a0', 'c0']);
      expect(
        (slot.player as _Player).plays,
        0,
        reason: 'stale native completion must not play',
      );
      latest.complete();
      await tester.pump();
      expect(maxInFlight, 1);
      expect((slot.player as _Player).plays, 1);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'navigation schedules current while an old speculative load finishes',
    (tester) async {
      final gates = List.generate(3, (_) => Completer<void>());
      final opens = <int>[];
      final queue = _items(3);
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: _slots(),
        writeProgress: (_) async {},
        loadSlot: (_, file) {
          final index = int.parse(file.name.substring(1));
          opens.add(index);
          return gates[index].future;
        },
      );
      pool.reconcile(1, queue);
      pool.applyPending();
      gates[1].complete();
      await tester.pump();
      expect(opens, [1, 2]);
      pool.reconcile(0, queue);
      pool.applyPending();
      expect(opens, [
        1,
        2,
        0,
      ], reason: 'current must not wait for an unrelated native open');
      gates[0].complete();
      await tester.pump();
      expect((pool.slotFor(0)!.player as _Player).plays, 1);
      gates[2].complete();
      await tester.pump();
      expect((pool.slotFor(2)!.player as _Player).plays, 0);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'background stop waits for stale open and resume waits for that stop',
    (tester) async {
      final neighbourOpen = Completer<void>();
      final neighbourStop = Completer<void>();
      final trace = <String>[];
      final queue = _items(3);
      // Force the resumed next item to reuse its stopping slot. With three
      // slots, choosing the idle third slot is intentionally allowed instead.
      final slots = _slots(2);
      var neighbourOpens = 0;
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: slots,
        writeProgress: (_) async {},
        loadSlot: (_, file) async {
          trace.add('open:${file.name}');
          if (file.name == 'v2' && ++neighbourOpens == 1) {
            await neighbourOpen.future;
          }
        },
      );
      pool.reconcile(1, queue);
      pool.applyPending();
      await tester.pump();
      final current = pool.slotFor(1)!;
      final neighbour = pool.slotFor(2)!;
      final neighbourPlayer = neighbour.player as _Player;
      neighbourPlayer.onStop = () async {
        trace.add('stop:start');
        await neighbourStop.future;
        trace.add('stop:end');
      };
      expect(trace, ['open:v1', 'open:v2']);
      pool.setPreloadingEnabled(false);
      pool.applyPending();
      expect(pool.slotFor(2), isNull);
      expect(
        neighbourPlayer.stops,
        0,
        reason: 'stop must not overlap the old open',
      );
      expect(current.player.state.playing, isTrue);
      neighbourOpen.complete();
      await tester.pump();
      expect(neighbourPlayer.stops, 1);
      expect(neighbourPlayer.plays, 0);
      pool.setPreloadingEnabled(true);
      pool.applyPending();
      await tester.pump();
      expect(
        neighbourOpens,
        1,
        reason: 'a resumed open must wait for the late stop',
      );
      neighbourStop.complete();
      await tester.pump();
      expect(trace, [
        'open:v1',
        'open:v2',
        'stop:start',
        'stop:end',
        'open:v2',
      ]);
      expect(pool.slotFor(2), same(neighbour));
      expect(neighbourOpens, 2);
      expect((current.player as _Player).stops, 0);
      expect((current.player as _Player).plays, 1);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'background unload preserves a paused current item and restores neighbours',
    (tester) async {
      final queue = _items(3);
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: _slots(),
        writeProgress: (_) async {},
        loadSlot: (_, _) async {},
      );
      pool.reconcile(1, queue);
      pool.applyPending();
      await tester.pump();
      final current = pool.slotFor(1)!;
      final adjacent = [pool.slotFor(0)!, pool.slotFor(2)!];
      pool.userPaused = true;
      await current.player.pause();
      pool.setPreloadingEnabled(false);
      pool.applyPending();
      await tester.pump();
      expect(pool.slots.where((slot) => slot.loadedFile != null), [current]);
      expect(
        adjacent.every((slot) => (slot.player as _Player).stops == 1),
        isTrue,
      );
      expect(pool.userPaused, isTrue);
      pool.setPreloadingEnabled(true);
      pool.applyPending();
      await tester.pump();
      expect(pool.slotFor(0), isNotNull);
      expect(pool.slotFor(2), isNotNull);
      expect(pool.userPaused, isTrue);
      expect((current.player as _Player).plays, 1);
      expect(current.player.state.playing, isFalse);
      expect((current.player as _Player).stops, 0);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'dispose discards queued preloads and late completion cannot play',
    (tester) async {
      final gate = Completer<void>();
      final opens = <String>[];
      final slots = _slots();
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: slots,
        writeProgress: (_) async {},
        loadSlot: (_, file) {
          opens.add(file.name);
          return gate.future;
        },
      );
      pool.reconcile(1, _items(3));
      pool.applyPending();
      pool.dispose();
      gate.complete();
      await tester.pump();
      expect(opens, ['v1']);
      expect(
        slots.every((slot) => (slot.player as _Player).plays == 0),
        isTrue,
      );
    },
  );

  testWidgets('distant navigation chooses an idle slot before a busy preload', (
    tester,
  ) async {
    final oldPreload = Completer<void>();
    final opens = <String>[];
    final queue = _items(20);
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: _slots(),
      writeProgress: (_) async {},
      loadSlot: (_, file) async {
        opens.add(file.name);
        if (file.name == 'v2') await oldPreload.future;
      },
    );
    pool.reconcile(1, queue);
    pool.applyPending();
    await tester.pump();
    expect(opens, ['v1', 'v2']);
    final idle = pool.slotFor(0)!;
    pool.reconcile(10, queue);
    pool.applyPending();
    expect(pool.slotFor(10), same(idle));
    expect(opens, ['v1', 'v2', 'v10']);
    await tester.pump();
    expect((idle.player as _Player).plays, 1);
    oldPreload.complete();
    await tester.pump();
    expect(opens, ['v1', 'v2', 'v10', 'v11', 'v9']);
    pool.dispose();
    await tester.pump();
  });

  testWidgets(
    'replacing three items unloads unused slots and rejects an old reload',
    (tester) async {
      final oldReload = Completer<void>();
      var reloading = false;
      final writes = <String>[];
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: _slots(),
        writeProgress: (progress) async => writes.add(progress.file.name),
        loadSlot: (_, file) async {
          if (reloading && file.name == 'v2') await oldReload.future;
        },
      );
      pool.reconcile(1, _items(3));
      pool.applyPending();
      await tester.pump();
      final unused = [pool.slotFor(0)!, pool.slotFor(2)!];
      reloading = true;
      pool.reopen(pool.slotFor(2)!);
      pool.applyPending();
      pool.reconcile(0, _items(1, prefix: 'new'));
      pool.applyPending();
      await tester.pump();
      oldReload.complete();
      await tester.pump();
      expect(pool.slotFor(0)!.loadedFile!.name, 'new0');
      expect(
        unused.every(
          (slot) => slot.loadedFile == null && slot.feedIndex == null,
        ),
        isTrue,
      );
      for (final slot in unused) {
        final player = slot.player as _Player;
        expect(player.stops, 1);
        expect(player.plays, 0);
        expect(player.errors.hasListener, isFalse);
        player.errors.add('late old media error');
      }
      expect(pool.slotFor(0)!.error, isNull);
      expect(writes, ['v1']);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'clear then dispose before the next frame flushes captured progress',
    (tester) async {
      final file = _items(1).single.file;
      final slot = _slots(1).single
        ..feedIndex = 0
        ..loadedFile = file
        ..played = true;
      final writes = <String>[];
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: [slot],
        writeProgress: (progress) async => writes.add(progress.file.name),
      );
      pool.reconcile(-1, const []);
      pool.dispose();
      // No intervening frame and no explicit flush from the test/caller.
      await tester.idle();
      expect(writes, ['v0']);
    },
  );

  testWidgets('lifecycle unloads without frames and handles late PiP updates', (
    tester,
  ) async {
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: _slots(),
      writeProgress: (_) async {},
      loadSlot: (_, _) async {},
    );
    final ui = PlayerUiStore();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pool.reconcile(1, _items(3));
    pool.applyPending();
    await tester.pump();
    final current = pool.slotFor(1)!;
    final adjacent = [pool.slotFor(0)!, pool.slotFor(2)!];
    var builds = 0;
    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          builds++;
          useShortVideoPoolLifecycle(pool, playerUiStore: ui);
          return const SizedBox.shrink();
        },
      ),
    );
    final initialBuilds = builds;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.idle();
    expect(pool.preloadingEnabled, isTrue);
    expect(
      adjacent.every((slot) => (slot.player as _Player).stops == 0),
      isTrue,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);
    expect(pool.preloadingEnabled, isFalse);
    // No pump: both the lifecycle policy and native unload must run while
    // frames are disabled, rather than waiting for the application to resume.
    await tester.idle();
    expect(
      adjacent.every((slot) => (slot.player as _Player).stops == 1),
      isTrue,
    );
    expect(pool.slots.where((slot) => slot.loadedFile != null), [current]);
    expect(builds, initialBuilds);
    expect(current.player.state.playing, isTrue);
    expect((current.player as _Player).stops, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.idle();
    ui.updatePictureInPicture(true);
    await tester.idle();
    expect(pool.preloadingEnabled, isTrue);
    expect(pool.slotFor(0), isNotNull);
    expect(pool.slotFor(2), isNotNull);
    expect(builds, initialBuilds);
    ui.updatePictureInPicture(false);
    await tester.idle();
    expect(pool.preloadingEnabled, isFalse);
    expect(
      adjacent.every((slot) => (slot.player as _Player).stops == 2),
      isTrue,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.idle();
    expect(
      pool.preloadingEnabled,
      isFalse,
      reason: 'restore only when actually resumed',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.idle();
    expect(pool.preloadingEnabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    pool.dispose();
    await ui.dispose();
  });
}
