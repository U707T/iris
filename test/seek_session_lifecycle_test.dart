import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';

MediaPlayer _player({
  required Future<void> Function(Duration) seek,
  required Future<void> Function() play,
}) => MediaPlayer(
  isInitializing: false,
  isPlaying: true,
  position: Duration.zero,
  duration: const Duration(minutes: 10),
  buffer: Duration.zero,
  width: 0,
  height: 0,
  saveProgress: () async {},
  play: play,
  pause: () async {},
  backward: (_) async {},
  forward: (_) async {},
  stepBackward: () async {},
  stepForward: () async {},
  seek: seek,
);

void main() {
  testWidgets('old slow seek cannot resume a new drag', (tester) async {
    final gate = Completer<void>();
    final preview = ValueNotifier<Duration?>(null);
    var plays = 0;
    final player = _player(
      seek: (_) => gate.future,
      play: () async {
        plays++;
      },
    );
    final session = SeekSession(readPlayer: () => player, preview: preview);
    session.start(Duration.zero);
    session.seekTo(const Duration(seconds: 20));
    session.end();
    session.start(const Duration(seconds: 30));
    gate.complete();
    await tester.pump();
    expect(plays, 0);
    expect(session.isActive, isTrue);
    expect(preview.value, const Duration(seconds: 30));
    session.dispose();
    preview.dispose();
  });

  testWidgets('old seek cannot resume a changed media entry', (tester) async {
    final gate = Completer<void>();
    final preview = ValueNotifier<Duration?>(null);
    var entry = 1;
    var plays = 0;
    final player = _player(
      seek: (_) => gate.future,
      play: () async {
        plays++;
      },
    );
    final session = SeekSession(
      readPlayer: () => player,
      readIdentity: () => entry,
      preview: preview,
    );
    session.start(Duration.zero);
    session.seekTo(const Duration(seconds: 20));
    session.end();
    entry = 2;
    gate.complete();
    await tester.pump();
    expect(plays, 0);
    expect(preview.value, isNull);
    session.dispose();
    preview.dispose();
  });

  testWidgets(
    'end then dispose clears owned preview without clearing another owner',
    (tester) async {
      final gate = Completer<void>();
      final preview = ValueNotifier<Duration?>(null);
      final player = _player(seek: (_) => gate.future, play: () async {});
      final first = SeekSession(readPlayer: () => player, preview: preview);
      first.start(Duration.zero);
      first.seekTo(const Duration(seconds: 20));
      first.end();
      first.dispose();
      expect(preview.value, isNull);
      final second = SeekSession(readPlayer: () => player, preview: preview);
      second.start(const Duration(seconds: 40));
      first.dispose();
      expect(preview.value, const Duration(seconds: 40));
      second.dispose();
      gate.complete();
      await tester.pump();
      preview.dispose();
    },
  );
}
