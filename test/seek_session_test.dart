import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/seek_gesture.dart';
import 'package:iris/pages/player/gesture/seek_session.dart';

/// 拖动 seek 会话（主窗口横滑 / 短视频横滑 / 进度条共用同一份）：
/// - 开始拖动时若正在播放 -> 暂停，松手后恢复；
/// - **拖动中不发 seek**（只更新预览），手指停住 [SeekSession.settleDelay] 后才让画面跟上；
/// - 松手精确 seek 最终位置，落定后再收起预览（避免进度条闪一下）；
/// - 预览值走共享 ValueNotifier。
void main() {
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
    seeks = [];
    playCalls = 0;
    pauseCalls = 0;
    preview = ValueNotifier(null);
  });

  tearDown(() => preview.dispose());

  SeekSession build(MediaPlayer player) => SeekSession(
        readPlayer: () => player,
        preview: preview,
        // 测试里把「停住」的等待压到最短
        settleDelay: const Duration(milliseconds: 10),
      );

  test('播放中拖动: 暂停 -> 预览跟手(不 seek) -> 停住才 seek -> 松手补发并续播', () async {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 5));
    expect(pauseCalls, 1);
    expect(seeks, isEmpty, reason: '起手不发 seek');
    expect(preview.value, const Duration(seconds: 5));

    session.seekTo(const Duration(seconds: 20));
    session.seekTo(const Duration(seconds: 30));
    expect(preview.value, const Duration(seconds: 30), reason: '预览立即跟手');
    expect(seeks, isEmpty, reason: '拖动中一次 seek 都不发');

    // 手指停住 -> 让画面跟上（只发一次，不是节流循环）
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seeks, [const Duration(seconds: 30)]);

    session.seekTo(const Duration(seconds: 40));
    session.end();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(seeks.last, const Duration(seconds: 40), reason: '松手精确落定');
    expect(playCalls, 1, reason: '原本在播放 -> 恢复');
    expect(preview.value, isNull, reason: '落定后收起预览');
  });

  test('拖动中持续移动: 完全不解码 (连续 20 次位移只产生 1 次 seek)', () async {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 5));
    for (var i = 1; i <= 20; i++) {
      session.dragTo(i * 30.0);
      // 每帧都在动，停住计时器一直被重置
    }
    expect(seeks, isEmpty, reason: '手指没停过 -> 一次 seek 都没有');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seeks, hasLength(1), reason: '停住后只补一次');
  });

  test('停住过（画面已到位）: 松手不再重复 seek，直接续播', () async {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 5));
    session.seekTo(const Duration(seconds: 30));
    // 停住 -> 画面已经跳到 30s
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seeks, [const Duration(seconds: 30)]);

    session.end();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(seeks, [const Duration(seconds: 30)],
        reason: '画面已在目标位置，松手不该再 seek 一次（否则白闪）');
    expect(playCalls, 1);
    expect(preview.value, isNull);
  });

  test('暂停中拖动: 松手不恢复播放', () async {
    final player = buildPlayer(playing: false);
    final session = build(player);

    session.start(const Duration(seconds: 3));
    expect(pauseCalls, 0);
    session.seekTo(const Duration(seconds: 4));
    session.end();
    await Future<void>.delayed(const Duration(milliseconds: 200));

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

  test('目标没变化时不重复通知（同一帧重复回调不重建 UI）', () {
    final player = buildPlayer(playing: false);
    final session = build(player);
    var notifications = 0;
    preview.addListener(() => notifications++);

    session.start(const Duration(seconds: 10));
    session.dragTo(30);
    final afterFirst = notifications;

    // 同一位移重复上报（抖动 / 事件重发）：目标没变就不该再通知
    session.dragTo(30);
    session.dragTo(30);
    expect(notifications, afterFirst);
  });

  test('dispose 后 end 不会向已销毁播放器发 play', () async {
    final player = buildPlayer(playing: true);
    final session = build(player);

    session.start(const Duration(seconds: 3));
    expect(pauseCalls, 1);

    session.dispose();
    session.end();
    await Future<void>.delayed(const Duration(milliseconds: 200));

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
