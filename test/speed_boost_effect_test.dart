import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/widgets/speed_boost_effect.dart';

/// 长按加速光效 (主播放界面 / 短视频模式共用) 测试:
/// - 隐藏时不渲染光带, 显示时左右各一道
/// - 两道光带贴着画面左右边缘、竖直居中, 中央区域保持干净 (无文字)
/// - 隐藏后控制器停掉 (可以 pumpAndSettle, 不会一直有帧)

Future<void> _pumpEffect(WidgetTester tester, bool visible) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [SpeedBoostEffect(visible: visible)],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('隐藏时不显示光带, 显示时左右各一道', (tester) async {
    await _pumpEffect(tester, false);
    await tester.pumpAndSettle();
    expect(find.byKey(SpeedBoostEffect.leftGlowKey), findsNothing);
    expect(find.byKey(SpeedBoostEffect.rightGlowKey), findsNothing);

    await _pumpEffect(tester, true);
    await tester.pump();
    expect(find.byKey(SpeedBoostEffect.leftGlowKey), findsOneWidget);
    expect(find.byKey(SpeedBoostEffect.rightGlowKey), findsOneWidget);

    // 收起后光效消失 (此时无常驻动画, 可以 settle)
    await _pumpEffect(tester, false);
    await tester.pumpAndSettle();
    expect(find.byKey(SpeedBoostEffect.leftGlowKey), findsNothing);
    expect(find.byKey(SpeedBoostEffect.rightGlowKey), findsNothing);
  });

  testWidgets('光带贴左右边缘、竖直居中, 中央不显示倍速文字', (tester) async {
    await _pumpEffect(tester, true);
    await tester.pump();

    final size = tester.getSize(find.byType(SpeedBoostEffect));
    final left = tester.getCenter(find.byKey(SpeedBoostEffect.leftGlowKey));
    final right = tester.getCenter(find.byKey(SpeedBoostEffect.rightGlowKey));

    expect(left.dx, lessThan(size.width * 0.1));
    expect(right.dx, greaterThan(size.width * 0.9));
    expect((left.dy - size.height / 2).abs(), lessThan(1.0));
    expect((right.dy - size.height / 2).abs(), lessThan(1.0));

    // 只用光效示意, 不显示倍速文字
    expect(find.byType(Text), findsNothing);

    // 让呼吸动画停下来, 不影响后续测试
    await _pumpEffect(tester, false);
    await tester.pumpAndSettle();
  });
}
