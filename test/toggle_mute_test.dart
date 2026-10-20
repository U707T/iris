import 'package:flutter_test/flutter_test.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/toggle_mute_or_restore.dart';

/// 音量按钮点击语义:
/// - "静音 + 音量 0" 点一次要真的出声（旧实现只调音量、不解静音 → 没反应）
/// - 普通静音 / 取消静音
void main() {
  final store = useAppStore();

  setUp(() async {
    await store.updateMute(false);
    await store.updateVolume(50);
  });

  test('静音 + 音量 0: 点一次同时取消静音并恢复音量', () async {
    await store.updateMute(true);
    await store.updateVolume(0);

    await toggleMuteOrRestore();

    expect(store.state.isMuted, isFalse);
    expect(store.state.volume, 80);
  });

  test('音量 0 未静音: 恢复到 80', () async {
    await store.updateVolume(0);

    await toggleMuteOrRestore();

    expect(store.state.isMuted, isFalse);
    expect(store.state.volume, 80);
  });

  test('正常音量: 切换静音 / 取消静音', () async {
    await toggleMuteOrRestore();
    expect(store.state.isMuted, isTrue);
    expect(store.state.volume, 50);

    await toggleMuteOrRestore();
    expect(store.state.isMuted, isFalse);
    expect(store.state.volume, 50);
  });
}
