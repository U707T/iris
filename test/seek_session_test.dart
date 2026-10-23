import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';

/// 拖动 seek 会话（主窗口横滑 / 短视频横滑 / 短视频进度条共用同一份）：
/// - 开始拖动时若正在播放 -> 暂停，松手后恢复；
/// - 起手不发 seek（避免「一按就顿一下」）；
/// - 预览 seek 按 120ms 节流，松手补发最终位置；
/// - 预览值走共享 ValueNotifier，松手后保留一小段时间再收起。
void main() {
  late DateTime now;
  late List<Duration> seeks;
  late int playCalls;
  late int pauseCalls;
  late ValueNotifier<Duration?> preview;

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
    preview = ValueNotifier(null);
  });

  tearDown(() => preview.dispose());

  SeekSession build(MediaPlayer player) => SeekSession(
        readPlayer: () => player,
        preview: preview,
        clock: () => now,
      );

  test('播放中拖动: 暂停 -> 节流 seek -> 松手补发并恢复播放', () {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 5));
    expect(pauseCalls, 1);
    expect(seeks, isEmpty, reason: '起手不发 seek');
    expect(preview.value, const Duration(seconds: 5));

    session.seekTo(const Duration(seconds: 6));
    expect(seeks, [const Duration(seconds: 6)], reason: '第一次立即 seek');

    session.seekTo(const Duration(seconds: 7));
    expect(seeks, hasLength(1), reason: '节流期内不发送');
    expect(preview.value, const Duration(seconds: 7), reason: '预览立即跟手');

    now = now.add(const Duration(milliseconds: 120));
    session.seekTo(const Duration(seconds: 8));
    expect(seeks.last, const Duration(seconds: 8));

    session.seekTo(const Duration(seconds: 9));
    session.end();

    expect(seeks.last, const Duration(seconds: 9), reason: '松手补发最终位置');
    expect(playCalls, 1, reason: '原本在播放 -> 恢复');
  });

  test('暂停中拖动: 松手不恢复播放', () {
    final player = buildPlayer(playing: false);
    final session = build(player);

    session.start(const Duration(seconds: 3));
    expect(pauseCalls, 0);
    session.seekTo(const Duration(seconds: 4));
    session.end();

    expect(playCalls, 0);
  });

  test('累计位移换算: 3px = 1 秒, 且夹在 0~duration', () {
    final player = buildPlayer(playing: false);
    final session = build(player);

    session.start(const Duration(seconds: 10));
    session.dragTo(30);
    expect(session.target, const Duration(seconds: 20));
    expect(preview.value, const Duration(seconds: 20));

    session.dragTo(-3000);
    expect(session.target, Duration.zero, reason: '左滑到负值夹到 0');

    session.dragTo(100000);
    expect(session.target, const Duration(minutes: 1), reason: '右滑夹到时长');
  });

  test('dispose 后 end 不会向已销毁播放器发 play', () {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 3));
    expect(pauseCalls, 1);

    session.dispose();
    session.end();

    expect(playCalls, 0);
  });

  test('没有 start 时 seek 被忽略', () {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.seekTo(const Duration(seconds: 2));
    expect(seeks, isEmpty);
    expect(preview.value, isNull);
  });

  test('cancel 立即收起预览（双指缩放打断）', () {
    final player = buildPlayer(playing: false);
    final session = build(player);

    session.start(const Duration(seconds: 3));
    session.seekTo(const Duration(seconds: 5));
    expect(preview.value, isNotNull);

    session.cancel();
    expect(preview.value, isNull);
    expect(session.isActive, isFalse);
  });

  group('手势方向判定（两个模式同一套阈值）', () {
    test('未超过 8dp 死区时保持未定', () {
      expect(resolveGestureAxis(dxDp: 5, dyDp: 0), isNull);
      expect(resolveGestureAxis(dxDp: 0, dyDp: 7), isNull);
    });

    test('横向明显占优 -> 进度', () {
      expect(resolveGestureAxis(dxDp: 30, dyDp: 5), GestureAxis.horizontal);
      expect(resolveGestureAxis(dxDp: -30, dyDp: 5), GestureAxis.horizontal);
    });

    test('纵向明显占优 -> 音量 / 亮度 / 翻页', () {
      expect(resolveGestureAxis(dxDp: 5, dyDp: 30), GestureAxis.vertical);
      expect(resolveGestureAxis(dxDp: -5, dyDp: -30), GestureAxis.vertical);
    });

    test('45 度斜滑两个方向都不锁定（避免中途横跳）', () {
      expect(resolveGestureAxis(dxDp: 20, dyDp: 20), isNull);
      expect(resolveGestureAxis(dxDp: 25, dyDp: 20), isNull);
    });
  });
}
