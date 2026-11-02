import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/overlays/controls_auto_hide.dart';

/// 控制层自动隐藏的行为契约（对齐 YouTube / VLC / mpv / PotPlayer / IINA）。
///
/// 这里只测「什么时候该收起」，不测渲染 —— 渲染由
/// `controls_overlay_test.dart` 覆盖。
void main() {
  late bool controls;
  late bool minimal;
  late ControlsAutoHide autoHide;

  ControlsAutoHide build({Duration delay = const Duration(milliseconds: 50)}) =>
      ControlsAutoHide(
        readControls: () => controls,
        writeControls: (v) => controls = v,
        readMinimal: () => minimal,
        writeMinimal: (v) => minimal = v,
        delay: delay,
      );

  setUp(() {
    controls = true;
    minimal = false;
    autoHide = build();
  });

  tearDown(() => autoHide.dispose());

  Future<void> wait([int ms = 80]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('只在播放中倒计时', () {
    test('播放中: 到点收起控制栏', () async {
      autoHide
        ..playing = true
        ..sync();
      await wait();
      expect(controls, isFalse);
    });

    test('暂停: 控制栏常驻（YouTube / VLC / mpv 一致）', () async {
      autoHide
        ..playing = false
        ..sync();
      await wait();
      expect(controls, isTrue);
    });

    test('播放 -> 暂停时, 已经排上的收起被取消', () async {
      autoHide
        ..playing = true
        ..sync();
      autoHide
        ..playing = false
        ..sync();
      await wait();
      expect(controls, isTrue);
    });

    test('播放 -> 暂停后再恢复播放, 重新开始倒计时', () async {
      autoHide
        ..playing = false
        ..sync();
      await wait(20);
      autoHide
        ..playing = true
        ..sync();
      await wait(20);
      expect(controls, isTrue, reason: '恢复播放后还没到延迟');
      await wait();
      expect(controls, isFalse);
    });
  });

  group('正在使用时不收起', () {
    test('指针停在控制栏上: 不收; 移开后重新计时', () async {
      autoHide
        ..hovering = true
        ..sync();
      await wait();
      expect(controls, isTrue);

      autoHide
        ..hovering = false
        ..sync();
      await wait();
      expect(controls, isFalse);
    });

    test('拖动 seek 中: 不收', () async {
      autoHide
        ..seeking = true
        ..sync();
      await wait();
      expect(controls, isTrue);
    });

    test('有弹层盖着: 不收; 关掉弹层后重新计时（不需要调用方补重置）', () async {
      autoHide
        ..overlayOpen = true
        ..sync();
      await wait();
      expect(controls, isTrue);

      autoHide
        ..overlayOpen = false
        ..sync();
      await wait();
      expect(controls, isFalse);
    });

    test('关掉「自动隐藏控制栏」: 永不收起', () async {
      autoHide
        ..enabled = false
        ..sync();
      await wait();
      expect(controls, isTrue);
    });
  });

  group('唤出 / 收起', () {
    test('show 立刻可见, 并重新计时', () async {
      autoHide.hide();
      expect(controls, isFalse);

      autoHide.show();
      expect(controls, isTrue);
      await wait();
      expect(controls, isFalse);
    });

    test('show 会顺手收掉迷你进度（避免两套读数同时出现）', () async {
      minimal = true;
      autoHide.show();
      expect(minimal, isFalse);
    });
  });

  group('迷你进度（方向键 / 横滑的瞬时读数）', () {
    test('关掉「自动隐藏」也会自己消失', () async {
      autoHide
        ..enabled = false
        ..playing = false;
      autoHide.hide(); // 控制栏先收起, 此时才会出现迷你进度
      autoHide.showMinimal();
      expect(minimal, isTrue);

      await wait();
      expect(minimal, isFalse, reason: '瞬时读数不该因为设置项而永久驻留');
    });

    test('控制栏在屏幕上时不重复显示迷你进度, 只续期', () async {
      autoHide.showMinimal();
      expect(minimal, isFalse);
      expect(controls, isTrue);
    });

    test('拖动中不收起, 松手后重新计时', () async {
      autoHide.hide();
      autoHide
        ..seeking = true
        ..sync();
      autoHide.showMinimal();
      await wait();
      expect(minimal, isTrue);

      autoHide
        ..seeking = false
        ..sync();
      await wait();
      expect(minimal, isFalse);
    });
  });

  group('宿主 / 收尾', () {
    test('短视频模式挂起调度', () async {
      autoHide
        ..active = false
        ..sync();
      await wait();
      expect(controls, isTrue);
    });

    test('dispose 后不再改状态', () async {
      autoHide
        ..playing = true
        ..sync();
      autoHide.dispose();
      await wait();
      expect(controls, isTrue, reason: 'dispose 已经取消了计时器');
    });
  });
}
