import 'package:flutter_test/flutter_test.dart';
import 'package:iris/pages/player/gesture/seek_hub.dart';
import 'package:iris/pages/player/overlays/controls_auto_hide.dart';
import 'package:iris/store/use_player_ui_store.dart';

/// 主窗口「控制层唤出 / 收起」的串联行为：
///
/// 这一层以前是 `Player.build` 里的两套 Timer，现在由 [ControlsAutoHide] 统一
/// 调度。这里验证最终手感：
///
/// - 播放中静置到延迟 → 自动收起
/// - 暂停 / 播完 / 出错 → 不再收起（控制栏常驻）
/// - 收起后只弹迷你进度，不弹整套控制栏
/// - 唤出控制栏时迷你进度立刻让位
void main() {
  late bool controls;
  late bool minimal;
  late ControlsAutoHide autoHide;

  setUp(() {
    controls = true;
    minimal = false;
    seekHub.reset();
    autoHide = ControlsAutoHide(
      readControls: () => controls,
      writeControls: (v) => controls = v,
      readMinimal: () => minimal,
      writeMinimal: (v) => minimal = v,
      delay: const Duration(milliseconds: 40),
    );
    usePlayerUiStore().updateIsShowControl(true);
    usePlayerUiStore().updateIsShowProgress(false);
    usePlayerUiStore().updateIsSeeking(false);
    usePlayerUiStore().updateIsHovering(false);
  });

  tearDown(() => autoHide.dispose());

  test('播放中: 显式唤出后到点自动收起', () async {
    autoHide
      ..playing = true
      ..hide()
      ..show();
    expect(controls, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(controls, isFalse);
  });

  test('暂停: 唤出后不会自动收起（暂停即常驻）', () async {
    autoHide
      ..playing = false
      ..hide()
      ..show();

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(controls, isTrue, reason: '暂停时用户随时要能点播放/拖动进度');
  });

  test('播放结束(isPlaying=false): 与暂停一致, 控制栏留下', () async {
    autoHide
      ..playing = true
      ..hide()
      ..show();
    // 播放结束: 播放状态翻成 false
    autoHide
      ..playing = false
      ..sync();

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(controls, isTrue);
  });

  test('播放出错: 错误提示在, 控制栏不被收走', () async {
    // Player 里是 playing = isPlaying && error == null
    autoHide
      ..playing = false
      ..hide()
      ..show();

    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(controls, isTrue);
  });

  test('收起后只弹迷你进度, 不弹整套控制栏', () async {
    autoHide
      ..playing = true
      ..hide();

    autoHide.showMinimal();
    expect(controls, isFalse);
    expect(minimal, isTrue);

    // 迷你进度也会自己消失（设置里关掉自动隐藏时同样如此）
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(minimal, isFalse);
  });

  test('唤出控制栏时, 迷你进度立刻让位', () async {
    autoHide
      ..playing = true
      ..hide();
    autoHide.showMinimal();
    expect(minimal, isTrue);

    autoHide.show();
    expect(minimal, isFalse);
    expect(controls, isTrue);
  });
}
