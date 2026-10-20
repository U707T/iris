import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/short_video/short_video_scrub.dart';

/// 短视频进度拖动会话:
/// - 开始拖动时若正在播放 -> 暂停, 松手后恢复;
/// - 预览 seek 按 120ms 节流, 松手补发最终位置;
/// - 未开始时忽略 seek。
void main() {
  late DateTime now;
  late List<Duration> seeks;
  late int playCalls;
  late int pauseCalls;

  MediaPlayer buildPlayer({required bool playing}) => MediaPlayer(
        isInitializing: false,
        isPlaying: playing,
        position: Duration.zero,
        duration: const Duration(minutes: 1),
        buffer: Duration.zero,
        width: 0,
        height: 0,
        saveProgress: () async {},
        play: () async => playCalls++,
        pause: () async => pauseCalls++,
        backward: (_) async {},
        forward: (_) async {},
        stepBackward: () async {},
        stepForward: () async {},
        seek: (target) async => seeks.add(target),
      );

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    seeks = [];
    playCalls = 0;
    pauseCalls = 0;
  });

  test('播放中拖动: 暂停 -> 节流 seek -> 松手补发并恢复播放', () {
    final player = buildPlayer(playing: true);
    final scrub = ShortVideoScrubSession(
      readPlayer: () => player,
      clock: () => now,
    );

    scrub.start(const Duration(seconds: 5));
    expect(pauseCalls, 1);
    expect(seeks, [const Duration(seconds: 5)], reason: '第一次立即 seek');

    scrub.seek(const Duration(seconds: 6));
    scrub.seek(const Duration(seconds: 7));
    expect(seeks, hasLength(1), reason: '节流期内不发送');

    now = now.add(const Duration(milliseconds: 120));
    scrub.seek(const Duration(seconds: 8));
    expect(seeks.last, const Duration(seconds: 8));

    scrub.seek(const Duration(seconds: 9));
    scrub.end();

    expect(seeks.last, const Duration(seconds: 9), reason: '松手补发最终位置');
    expect(playCalls, 1, reason: '原本在播放 -> 恢复');
    expect(scrub.preview.value, const Duration(seconds: 9));
  });

  test('暂停中拖动: 松手不恢复播放', () {
    final player = buildPlayer(playing: false);
    final scrub = ShortVideoScrubSession(
      readPlayer: () => player,
      clock: () => now,
    );

    scrub.start(const Duration(seconds: 3));
    expect(pauseCalls, 0);
    scrub.end();

    expect(playCalls, 0);
  });

  test('没有 start 时 seek 被忽略', () {
    final player = buildPlayer(playing: true);
    final scrub = ShortVideoScrubSession(
      readPlayer: () => player,
      clock: () => now,
    );

    scrub.seek(const Duration(seconds: 2));
    expect(seeks, isEmpty);
    expect(scrub.preview.value, isNull);
  });
}
