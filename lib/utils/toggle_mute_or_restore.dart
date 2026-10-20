import 'package:iris/store/use_app_store.dart';

/// 音量按钮的点击语义（主界面 / 短视频共用）。
///
/// - 静音，或音量为 0：取消静音；音量为 0 时恢复到 80
/// - 其余情况：静音
///
/// 只判断 `volume == 0` 是不够的：先拖到 0、再按 Ctrl+M 会进入
/// “静音 + 音量 0”，此时点按钮只把音量调回 80、`isMuted` 仍是 true，
/// 用户看到的是图标不变、也没有声音。
Future<void> toggleMuteOrRestore([AppStore? store]) async {
  final appStore = store ?? useAppStore();
  final volume = appStore.state.volume;
  final isMuted = appStore.state.isMuted;

  if (isMuted || volume == 0) {
    if (isMuted) await appStore.updateMute(false);
    if (volume == 0) await appStore.updateVolume(80);
  } else {
    await appStore.toggleMute();
  }
}
