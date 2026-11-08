import 'package:flutter/foundation.dart';
import 'package:iris/models/store/app_state.dart';
import 'package:iris/store/use_app_store.dart';

/// 打开「横屏模式」之前的屏幕方向。
///
/// 关闭时恢复到它, 而不是写死 [ScreenOrientation.device] —— 用户在设置里
/// 选过「纵向」的, 不该因为按了一次横屏开关就被悄悄改掉。
ScreenOrientation _restoreOrientation = ScreenOrientation.device;

/// 在「横屏」与「打开前的方向」之间切换。
///
/// 为什么复用 AppState.orientation, 而不是另开一个开关:
/// 真正生效的只有 `SystemChrome.setPreferredOrientations` 这一条路径
/// (见 `use_orientation.dart`), 两套状态并存迟早会打架。这里既是控制栏
/// 的快捷入口, 也是设置里「屏幕方向」的同一份状态。
///
/// 用途: MIUI / HyperOS 等系统小窗、分屏会按 Activity 的
/// requestedOrientation 决定窗口形状 —— 手动锁横屏后, 小窗才会按视频
/// 比例横着铺开, 而不是被挤成竖条。
Future<void> toggleLandscapeMode() async {
  final store = useAppStore();
  final current = store.state.orientation;

  if (current == ScreenOrientation.landscape) {
    await store.updateOrientation(_restoreOrientation);
    return;
  }

  _restoreOrientation = current;
  await store.updateOrientation(ScreenOrientation.landscape);
}

/// 测试用: 清掉记住的方向 (模块级状态会在用例之间互相影响)
@visibleForTesting
void resetLandscapeModeRestore() {
  _restoreOrientation = ScreenOrientation.device;
}
