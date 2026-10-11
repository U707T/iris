import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/short_video/short_video_wheel.dart';

/// ShortVideoWheelSwitcher 的增量规则单测 (与 UI 解耦, 时钟可注入)。
void main() {
  test('累积到阈值才切换: 细碎增量也能攒起来', () {
    final switches = <int>[];
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final wheel = ShortVideoWheelSwitcher(
      onSwitch: switches.add,
      clock: () => now,
    );

    // 每次 10px: 攒到 30px 阈值才切换
    wheel.handleScroll(10);
    expect(switches, isEmpty);
    wheel.handleScroll(10);
    expect(switches, isEmpty);
    wheel.handleScroll(10);
    expect(switches, [1]); // 向下滚 = 下一条
  });

  test('单次大增量立即切换; 冷却期内丢弃后续增量', () {
    final switches = <int>[];
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final wheel = ShortVideoWheelSwitcher(
      onSwitch: switches.add,
      clock: () => now,
    );

    wheel.handleScroll(100);
    expect(switches, [1]);

    // 冷却期 (420ms) 内再滚: 丢弃, 避免一次跳过太多视频
    now = now.add(const Duration(milliseconds: 200));
    wheel.handleScroll(-100);
    expect(switches, [1]);

    // 冷却结束后: 反向滚动切换上一条
    now = now.add(const Duration(milliseconds: 300));
    wheel.handleScroll(-100);
    expect(switches, [1, -1]);
  });

  test('反向增量打断累积 (从当前增量重新计数)', () {
    final switches = <int>[];
    final now = DateTime(2026, 1, 1, 12, 0, 0);
    final wheel = ShortVideoWheelSwitcher(
      onSwitch: switches.add,
      clock: () => now,
    );

    wheel.handleScroll(20); // 未到阈值
    wheel.handleScroll(-20); // 反向: 重新从 -20 开始
    expect(switches, isEmpty);
    wheel.handleScroll(-20); // 累计 -40 -> 上一条
    expect(switches, [-1]);
  });

  test('两次事件间隔过久: 重新开始累积', () {
    final switches = <int>[];
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final wheel = ShortVideoWheelSwitcher(
      onSwitch: switches.add,
      clock: () => now,
    );

    wheel.handleScroll(20);
    now = now.add(const Duration(milliseconds: 500)); // > 400ms 间隔
    wheel.handleScroll(20); // 重新计数: 20 < 30, 不切换
    expect(switches, isEmpty);
    wheel.handleScroll(15); // 20 + 15 = 35 -> 切换
    expect(switches, [1]);
  });
}
