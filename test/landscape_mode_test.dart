import 'package:flutter_test/flutter_test.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/landscape_mode.dart';

/// 「横屏模式」开关的语义:
/// - 打开 = 锁横屏 (系统小窗 / 分屏按横屏铺开)
/// - 关闭 = 回到打开前的方向, 不覆盖用户在设置里的选择
void main() {
  final store = useAppStore();

  setUp(() async {
    resetLandscapeModeRestore();
    await store.updateOrientation(ScreenOrientation.device);
  });

  test('从设备方向打开: 切到横屏, 再关回到设备方向', () async {
    expect(store.state.orientation, ScreenOrientation.device);

    await toggleLandscapeMode();
    expect(store.state.orientation, ScreenOrientation.landscape);

    await toggleLandscapeMode();
    expect(store.state.orientation, ScreenOrientation.device);
  });

  test('设置里选过纵向: 关闭横屏后回到纵向, 而不是设备方向', () async {
    await store.updateOrientation(ScreenOrientation.portrait);

    await toggleLandscapeMode();
    expect(store.state.orientation, ScreenOrientation.landscape);

    await toggleLandscapeMode();
    expect(store.state.orientation, ScreenOrientation.portrait);
  });

  test('连续开关: 不会把横屏本身记成"打开前的方向"', () async {
    await toggleLandscapeMode();
    await toggleLandscapeMode();
    await toggleLandscapeMode();

    expect(store.state.orientation, ScreenOrientation.landscape);
    await toggleLandscapeMode();
    expect(store.state.orientation, ScreenOrientation.device);
  });
}
