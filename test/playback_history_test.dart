import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/playback_history.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/progress.dart';

Progress _progress(String uri) => Progress(
  file: FileItem(name: 'a', uri: uri),
  dateTime: DateTime.utc(2026),
  position: const Duration(seconds: 20),
  duration: const Duration(minutes: 1),
);

void main() {
  test('history save waits for write and backend drain', () async {
    final write = Completer<void>();
    final drain = Completer<void>();
    var flushing = false;
    var completed = false;
    final save = savePlaybackHistory(
      _progress('/media/a.mp4'),
      write: (_) => write.future,
      flush: () {
        flushing = true;
        return drain.future;
      },
    );
    unawaited(
      save.then((_) {
        completed = true;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(flushing, isFalse);
    write.complete();
    await Future<void>.delayed(Duration.zero);
    expect(flushing, isTrue);
    expect(completed, isFalse);
    drain.complete();
    await save;
    expect(completed, isTrue);
  });

  test('temporary content grants never enter restorable history', () async {
    var writes = 0;
    var flushes = 0;
    await savePlaybackHistory(
      _progress('content://provider/video/1'),
      write: (_) async {
        writes++;
      },
      flush: () async {
        flushes++;
      },
    );
    expect(writes, 0);
    expect(flushes, 0);
    expect(canPersistPlaybackUri('CONTENT://provider/video/2'), isFalse);
    expect(canPersistPlaybackUri('https://example.test/a.mp4'), isTrue);
  });

  test('drain failures reach the caller before window destruction', () async {
    await expectLater(
      savePlaybackHistory(
        _progress('/media/a.mp4'),
        write: (_) async {},
        flush: () async {
          throw StateError('disk full');
        },
      ),
      throwsStateError,
    );
  });
}
