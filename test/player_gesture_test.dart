import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/player.dart';
import 'package:iris/pages/player/gesture/player_gesture_layer.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/gesture/seek_hud.dart';
import 'package:provider/provider.dart';

/// 统一手势层（主窗口与短视频模式共用）的行为契约：
/// - 双击左 / 右 1/3 = 快退 / 快进 + 中央 `±Ns` 提示，中间 1/3 = 交给调用方；
/// - 横滑 = 暂停 + 预览跟手 + 松手落定并续播；
/// - 竖滑在 allowVertical=false（短视频）时**不**接管，交给下层翻页；
/// - 未超过死区 / 斜滑时不锁定方向（不误触发）。
final List<Duration> seeks = [];
final List<int> forwards = [];
final List<int> backwards = [];
int pauseCalls = 0;
int playCalls = 0;
int middleTaps = 0;

MediaPlayer _player({Duration position = const Duration(seconds: 30)}) =>
    MediaPlayer(
      isInitializing: false,
      isPlaying: true,
      position: position,
      duration: const Duration(minutes: 10),
      buffer: Duration.zero,
      width: 0,
      height: 0,
      saveProgress: () async {},
      play: () async => playCalls++,
      pause: () async => pauseCalls++,
      backward: (s) async => backwards.add(s),
      forward: (s) async => forwards.add(s),
      stepBackward: () async {},
      stepForward: () async {},
      seek: (t) async => seeks.add(t),
    );

Future<void> _pump(
  WidgetTester tester, {
  bool allowVertical = true,
  int step = 5,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final player = _player();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Provider<MediaPlayer>.value(
          value: player,
          child: Stack(
            children: [
              // 生产代码里手势层始终在 Positioned.fill 内（有确定尺寸）；
              // 测试里同样要给满屏约束，否则 ColoredBox 会被松约束压成 0x0。
              Positioned.fill(
                child: PlayerGestureLayer(
                  readPlayer: () => player,
                  seekStepSeconds: () => step,
                  allowVertical: allowVertical,
                  onTap: () {},
                  onDoubleTapMiddle: () => middleTaps++,
                  onLongPressStart: () {},
                  onLongPressEnd: () {},
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Positioned.fill(
                child: SeekHudOverlay(controller: seekHub.hud),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  setUp(() {
    seeks.clear();
    forwards.clear();
    backwards.clear();
    pauseCalls = 0;
    playCalls = 0;
    middleTaps = 0;
    seekHub.reset();
  });

  testWidgets('双击右侧 1/3: 快进 + 中央提示', (tester) async {
    await _pump(tester, step: 7);
    await _doubleTapAt(tester, const Offset(560, 400));

    // 双击步进现在走毫秒精度的 seek（不再用 forward/backward 的秒级截断）
    expect(seeks, [const Duration(seconds: 37)]);
    expect(forwards, isEmpty);
    expect(backwards, isEmpty);
    expect(find.text('+7s'), findsOneWidget);

    // 跑完提示自动收起的定时器（否则测试框架报 pending timer）
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('+7s'), findsNothing);
  });

  testWidgets('双击左侧 1/3: 快退 + 中央提示', (tester) async {
    await _pump(tester, step: 7);
    await _doubleTapAt(tester, const Offset(40, 400));

    expect(seeks, [const Duration(seconds: 23)]);
    expect(forwards, isEmpty);
    expect(backwards, isEmpty);
    expect(find.text('-7s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('-7s'), findsNothing);
  });

  testWidgets('双击中间 1/3: 交给调用方 (不 seek)', (tester) async {
    await _pump(tester);
    await _doubleTapAt(tester, const Offset(300, 400));

    expect(middleTaps, 1);
    expect(seeks, isEmpty);
    expect(forwards, isEmpty);
    expect(backwards, isEmpty);

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('横滑: 暂停 -> 预览跟手 -> 松手补发并续播', (tester) async {
    await _pump(tester);

    // 从中心右滑 60px = +20 秒（3px/秒）
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(pauseCalls, 1, reason: '开始拖动即暂停');
    expect(seekHub.preview.value, isNotNull, reason: '预览立即可读');

    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(seekHub.preview.value, const Duration(seconds: 50),
        reason: '30s + 60px/3 = 50s');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks.last, const Duration(seconds: 50), reason: '松手落定最终位置');
    expect(playCalls, 1, reason: '原本在播 -> 续播');

    // 等预览保留期结束（600ms）后自动收起
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(seekHub.preview.value, isNull);
  });

  testWidgets('未超过死区: 不暂停、不 seek', (tester) async {
    await _pump(tester);

    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pauseCalls, 0);
    expect(seeks, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('45 度斜滑: 不锁定方向 (两个模式都不会乱跳)', (tester) async {
    await _pump(tester);

    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(30, 30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pauseCalls, 0, reason: '斜滑不进入进度拖动');
    expect(seeks, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('allowVertical=false (短视频): 竖滑不接管进度', (tester) async {
    await _pump(tester, allowVertical: false);

    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pauseCalls, 0);
    expect(seeks, isEmpty, reason: '纵向留给 PageView 翻页');
    await tester.pump(const Duration(milliseconds: 800));
  });
}
