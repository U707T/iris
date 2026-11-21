import 'package:flutter/widgets.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/file.dart';
import 'package:iris/pages/player/short_video/short_video_pool.dart';
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
  Future<void> dispose() async {
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCancellation extends Fake implements StreamSubscription<String> {
  _PendingCancellation(this.done);
  final Completer<void> done;
  @override
  Future<void> cancel() => done.future;
}

class _Video implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlayQueueItem _item(String uri) => PlayQueueItem(
  index: 0,
  file: FileItem(name: uri, uri: uri, type: ContentType.video),
);
ShortVideoSlot _slot() =>
    ShortVideoSlot(player: _Player(), controller: _Video());

void main() {
  testWidgets(
    'replacing a paused queue resets pause even when slot is reused',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final slot = _slot();
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: [slot],
        writeProgress: (_) async {},
        loadSlot: (_, _) async {},
      );
      pool.reconcile(0, [_item('/a.mp4')]);
      pool.applyPending();
      await tester.pump();
      await tester.pump();
      expect(
        (slot.player as _Player).plays,
        1,
        reason: 'first media was played before pausing',
      );
      expect(slot.initializing, isFalse);
      pool.userPaused = true;
      await slot.player.pause();
      pool.reconcile(0, [_item('/b.mp4')]);
      pool.applyPending();
      expect(pool.userPaused, isFalse);
      await tester.pump();
      await tester.pump();
      expect(slot.loadedFile!.uri, '/b.mp4');
      expect((slot.player as _Player).plays, 2);
      pool.dispose();
      await tester.pump();
    },
  );

  testWidgets('old error subscription cleanup cannot block a new media load', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = Completer<void>();
    final slot = _slot()..errorSubscription = _PendingCancellation(gate);
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: [slot],
      writeProgress: (_) async {},
      loadSlot: (_, _) async {},
    );
    pool.reconcile(0, [_item('/new.mp4')]);
    pool.applyPending();
    await tester.pump();
    expect((slot.player as _Player).plays, 1);
    expect(gate.isCompleted, isFalse);
    gate.complete();
    pool.dispose();
    await tester.pump();
  });

  testWidgets('backend errors during loading become retryable slot errors', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = Completer<void>();
    final slot = _slot();
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: [slot],
      writeProgress: (_) async {},
      loadSlot: (_, _) => gate.future,
    );
    pool.reconcile(0, [_item('/broken.mp4')]);
    pool.applyPending();
    await tester.pump();
    (slot.player as _Player).errors.add('cannot decode');
    gate.complete();
    await tester.pump();
    expect(slot.error, 'cannot decode');
    expect(slot.initializing, isFalse);
    expect(slot.played, isFalse);
    expect((slot.player as _Player).plays, 0);
    pool.dispose();
    await tester.pump();
  });

  test('flush waits for prior in-flight slot writes', () async {
    final gate = Completer<void>();
    final slot = _slot()
      ..loadedFile = _item('/a.mp4').file
      ..played = true;
    var completed = false;
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: [slot],
      writeProgress: (_) => gate.future,
    );
    final save = pool.saveSlotProgress(slot);
    final flush = pool.flushPendingSaves().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    gate.complete();
    await Future.wait([save, flush]);
    expect(completed, isTrue);
    slot.played = false;
    pool.dispose();
  });

  test(
    'content URIs without recorded durable grants never write history',
    () async {
      final slot = _slot()
        ..loadedFile = _item('content://provider/1').file
        ..played = true;
      var writes = 0;
      final pool = ShortVideoPool(
        buildMedia: (file) => Media(file.uri),
        initialSlots: [slot],
        writeProgress: (_) async {
          writes++;
        },
      );
      await pool.saveSlotProgress(slot);
      expect(writes, 0);
      pool.dispose();
    },
  );
  testWidgets('clearing the queue silences the old active slot immediately', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final slot = _slot();
    final pool = ShortVideoPool(
      buildMedia: (file) => Media(file.uri),
      initialSlots: [slot],
      writeProgress: (_) async {},
      loadSlot: (_, _) async {},
    );
    pool.reconcile(0, [_item('/a.mp4')]);
    pool.applyPending();
    await tester.pump();
    expect(slot.player.state.playing, isTrue);
    pool.reconcile(-1, const []);
    expect(slot.player.state.playing, isFalse);
    await tester.pump();
    pool.dispose();
    await tester.pump();
  });
}
