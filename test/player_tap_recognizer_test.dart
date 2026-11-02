import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/gesture/player_tap_recognizer.dart';

/// 单击 / 双击判定的契约。
///
/// 最关键的一条是**单击延迟**：Flutter 自带的
/// `TapGestureRecognizer + DoubleTapGestureRecognizer` 组合，单击要等
/// `kDoubleTapTimeout`（300ms）才触发 —— 「点一下画面，控制栏慢半拍才出来」。
/// 这里的 [PlayerTapGestureRecognizer] 让单击当场生效，双击在第一下之后补发。
void main() {
  Future<void> pumpRecognizer(
    WidgetTester tester, {
    required PlayerTapGestureRecognizer recognizer,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            PlayerTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PlayerTapGestureRecognizer>(
              () => recognizer,
              (_) {},
            ),
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets('单击立即触发（不再等 300ms 双击窗口）', (tester) async {
    var taps = 0;
    var doubles = 0;
    final recognizer = PlayerTapGestureRecognizer()
      ..onTap = (() => taps++)
      ..onDoubleTap = ((_) => doubles++);

    await pumpRecognizer(tester, recognizer: recognizer);
    await tester.tap(find.byType(SizedBox), warnIfMissed: false);
    // 只推进 1 帧: 单击必须已经生效
    await tester.pump(const Duration(milliseconds: 16));

    expect(taps, 1, reason: '单击当场触发，不等 kDoubleTapTimeout');
    expect(doubles, 0);

    // 走完双击窗口, 没有第二下 -> 不会再多出一次单击
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(doubles, 0);
  });

  testWidgets('两次快速点击: 第一下单击 + 第二下双击', (tester) async {
    final taps = <int>[];
    final doubles = <Offset>[];
    var clock = 0;
    final recognizer = PlayerTapGestureRecognizer()
      ..onTap = (() => taps.add(clock))
      ..onDoubleTap = ((position) => doubles.add(position));

    await pumpRecognizer(tester, recognizer: recognizer);

    final location = tester.getCenter(find.byType(SizedBox));
    await tester.tapAt(location);
    clock++;
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(location);
    clock++;
    await tester.pump(const Duration(milliseconds: 80));

    expect(taps, [0], reason: '第一下已经立刻生效');
    expect(doubles.length, 1, reason: '第二下补发双击');
    expect(doubles.single, location);
  });

  testWidgets('两次点击间隔超过窗口: 算两次独立单击', (tester) async {
    var taps = 0;
    var doubles = 0;
    final recognizer = PlayerTapGestureRecognizer()
      ..onTap = (() => taps++)
      ..onDoubleTap = ((_) => doubles++);

    await pumpRecognizer(tester, recognizer: recognizer);

    final location = tester.getCenter(find.byType(SizedBox));
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 80));

    expect(taps, 2);
    expect(doubles, 0);
  });

  testWidgets('拖动超过阈值: 不算点击（让位给拖动识别器）', (tester) async {
    var taps = 0;
    final recognizer = PlayerTapGestureRecognizer()..onTap = (() => taps++);

    await pumpRecognizer(tester, recognizer: recognizer);

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    expect(taps, 0);
  });

  testWidgets('慢一点的点（按住 350ms）也算单击', (tester) async {
    // 长按（倍速）是 500ms 才触发, 300~500ms 之间松开必须是单击,
    // 否则用户会觉得「点了没反应」
    var taps = 0;
    final recognizer = PlayerTapGestureRecognizer()..onTap = (() => taps++);

    await pumpRecognizer(tester, recognizer: recognizer);

    final gesture = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));

    expect(taps, 1);
  });

  testWidgets('deferSingleTap: 单击推迟到双击窗口之后（短视频的播放暂停）',
      (tester) async {
    var taps = 0;
    var doubles = 0;
    final recognizer =
        PlayerTapGestureRecognizer(deferSingleTap: () => true)
      ..onTap = (() => taps++)
      ..onDoubleTap = ((_) => doubles++);

    await pumpRecognizer(tester, recognizer: recognizer);

    final location = tester.getCenter(find.byType(SizedBox));
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 50));
    expect(taps, 0, reason: '还在双击窗口内, 不能先暂停一下');

    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1, reason: '窗口结束确认是单击');

    // 双击: 单击不能补发（否则双击中间 1/3 会多一次播放/暂停）
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 400));
    expect(doubles, 1);
    expect(taps, 1, reason: '双击时那次待确认的单击被撤销');
  });
}
