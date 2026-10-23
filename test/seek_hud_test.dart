import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/gesture/seek_hud.dart';

/// 快进 / 快退提示（主窗口与短视频模式共用同一份）：
/// - 双击：显示 `±Ns`，[SeekHudController.stepHold] 后自动收起；
/// - 拖动：显示「目标位置 / 总时长」，一直保留到松手；
/// - 连续操作以最后一次为准，旧定时器不会把新提示收掉。
void main() {
  late SeekHudController hud;

  setUp(() => hud = SeekHudController());
  tearDown(() => hud.dispose());

  test('双击提示: 立即显示, 到时间自动收起', () {
    expect(hud.value.value, isNull);

    hud.showStep(forward: true, seconds: 5);
    final state = hud.value.value!;
    expect(state.kind, SeekHudKind.step);
    expect(state.forward, isTrue);
    expect(state.seconds, 5);
  });

  test('拖动读数: 显示目标与总时长, 松手才收起', () {
    hud.showScrub(
      position: const Duration(seconds: 10),
      target: const Duration(seconds: 40),
      duration: const Duration(minutes: 2),
    );

    final state = hud.value.value!;
    expect(state.kind, SeekHudKind.scrub);
    expect(state.position, const Duration(seconds: 10));
    expect(state.target, const Duration(seconds: 40));
    expect(state.duration, const Duration(minutes: 2));

    hud.hideScrub();
    expect(hud.value.value, isNull);
  });

  test('拖动读数不会被「双击提示的自动收起」误清', () {
    hud.showStep(forward: true, seconds: 5);
    // 双击提示的定时器还在跑时开始拖动
    hud.showScrub(
      position: Duration.zero,
      target: const Duration(seconds: 20),
      duration: const Duration(minutes: 1),
    );
    expect(hud.value.value?.kind, SeekHudKind.scrub);
  });

  test('hideScrub 不影响非拖动状态的提示', () {
    hud.showStep(forward: false, seconds: 10);
    hud.hideScrub();
    expect(hud.value.value?.kind, SeekHudKind.step);
  });

  test('clear 立即清空', () {
    hud.showStep(forward: true, seconds: 5);
    hud.clear();
    expect(hud.value.value, isNull);
  });
}
