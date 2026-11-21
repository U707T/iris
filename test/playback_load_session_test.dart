import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/hooks/player/playback_load_session.dart';

void main() {
  test('stop while output is pending prevents opening old media', () async {
    final ready = Completer<void>();
    final errors = StreamController<String>.broadcast();
    final session = PlaybackLoadSession();
    var opens = 0;
    var plays = 0;
    final work = session.load(
      errors: errors.stream,
      ready: () => ready.future,
      open: () async {
        opens++;
      },
      firstFrame: () async {},
      shouldPlay: () => true,
      play: () async {
        plays++;
      },
    );
    session.invalidate();
    ready.complete();
    await work;
    expect(opens, 0);
    expect(plays, 0);
    session.dispose();
    await errors.close();
  });

  test(
    'late backend error is surfaced and prevents first-frame resume',
    () async {
      final frame = Completer<void>();
      final errors = StreamController<String>.broadcast(sync: true);
      final session = PlaybackLoadSession();
      var plays = 0;
      final work = session.load(
        errors: errors.stream,
        ready: () async {},
        open: () async {},
        firstFrame: () => frame.future,
        shouldPlay: () => true,
        play: () async {
          plays++;
        },
      );
      await Future<void>.delayed(Duration.zero);
      errors.add('network disconnected');
      expect(session.error, 'network disconnected');
      expect(session.initializing, isFalse);
      frame.complete();
      await work;
      expect(plays, 0);
      session.dispose();
      await errors.close();
    },
  );

  test(
    'dispose during open never publishes state or plays afterwards',
    () async {
      final opened = Completer<void>();
      final errors = StreamController<String>.broadcast();
      final session = PlaybackLoadSession();
      var plays = 0;
      var notifications = 0;
      session.addListener(() => notifications++);
      final work = session.load(
        errors: errors.stream,
        ready: () async {},
        open: () => opened.future,
        firstFrame: () async {},
        shouldPlay: () => true,
        play: () async {
          plays++;
        },
      );
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      session.dispose();
      opened.completeError(StateError('disposed backend'));
      await work;
      expect(plays, 0);
      expect(notifications, beforeDispose);
      await errors.close();
    },
  );

  test('a replacement load supersedes a pending first frame', () async {
    final frame = Completer<void>();
    final errors = StreamController<String>.broadcast();
    final session = PlaybackLoadSession();
    final played = <String>[];
    final first = session.load(
      identity: 'old',
      errors: errors.stream,
      ready: () async {},
      open: () async {},
      firstFrame: () => frame.future,
      shouldPlay: () => true,
      play: () async {
        played.add('old');
      },
    );
    await Future<void>.delayed(Duration.zero);
    await session.load(
      identity: 'new',
      errors: errors.stream,
      ready: () async {},
      open: () async {},
      firstFrame: () async {},
      shouldPlay: () => true,
      play: () async {
        played.add('new');
      },
    );
    frame.complete();
    await first;
    expect(played, ['new']);
    expect(session.loadedIdentity, 'new');
    session.invalidate();
    expect(session.loadedIdentity, isNull);
    session.dispose();
    await errors.close();
  });
  test(
    'old backend errors while new output is pending cannot fail the next load',
    () async {
      final ready = Completer<void>();
      final errors = StreamController<String>.broadcast(sync: true);
      final session = PlaybackLoadSession();
      var opens = 0;
      final work = session.load(
        errors: errors.stream,
        ready: () => ready.future,
        open: () async {
          opens++;
        },
        firstFrame: () async {},
        shouldPlay: () => false,
        play: () async {},
      );
      errors.add('old media failure');
      expect(session.error, isNull);
      ready.complete();
      await work;
      expect(opens, 1);
      expect(session.error, isNull);
      session.dispose();
      await errors.close();
    },
  );
}
