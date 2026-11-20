import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/pages/player/control_bar/volume_slider.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/toggle_mute_or_restore.dart';

/// 音量面板。
///
/// 以前用 `popover` 包：它把内容塞进一颗 **旧版** `Material` 里，而
/// `material_ui` 的 Slider 认的是新版 `Material` —— debug 下点开会直接
/// 断言 `No Material widget found`。控制栏的音量按钮已经让位给存储，
/// 面板改成从这里进，顺手换成标准 AlertDialog：Material 由对话框自己
/// 提供，主题也不会在两套 Material 之间漂移。
Future<void> showVolumeDialog(
  BuildContext context,
  void Function() showControl,
) async => showDialog<void>(
  context: context,
  builder: (context) {
    final t = getLocalizations(context);
    return AlertDialog(
      title: Text(t.volume),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      content: SizedBox(
        width: 280,
        child: VolumeControl(showControl: showControl),
      ),
    );
  },
);

class VolumeControl extends HookWidget {
  const VolumeControl({
    super.key,
    required this.showControl,
    this.showVolumeText = true,
    this.color,
    this.overlayColor,
  });

  final void Function() showControl;
  final bool showVolumeText;
  final Color? color;
  final WidgetStateProperty<Color?>? overlayColor;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final volume = useAppStore().select(context, (state) => state.volume);
    final isMuted = useAppStore().select(context, (state) => state.isMuted);

    // 滚轮只改内存, 400ms 后合并落盘一次; 关闭弹层时把最后一次结果补上。
    // (每格滚轮都写整份 AppState 会把加密存储写爆)
    final persistTimer = useRef<Timer?>(null);
    final isVolumeDirty = useRef(false);

    void schedulePersist() {
      isVolumeDirty.value = true;
      persistTimer.value?.cancel();
      persistTimer.value = Timer(const Duration(milliseconds: 400), () {
        isVolumeDirty.value = false;
        unawaited(useAppStore().updateVolume(useAppStore().state.volume));
      });
    }

    useEffect(() {
      return () {
        persistTimer.value?.cancel();
        if (isVolumeDirty.value) {
          isVolumeDirty.value = false;
          unawaited(useAppStore().updateVolume(useAppStore().state.volume));
        }
      };
    }, const []);

    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is! PointerScrollEvent) return;
        final delta = event.scrollDelta.dy;
        if (delta == 0) return;

        showControl();
        final appStore = useAppStore();
        if (appStore.state.isMuted) {
          unawaited(appStore.updateMute(false, persist: false));
        }
        // 读实时值而不是 build 时捕获的 volume: 快速滚轮下否则会丢步
        unawaited(
          appStore.updateVolume(
            appStore.state.volume + (delta < 0 ? 2 : -2),
            persist: false,
          ),
        );
        schedulePersist();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        textBaseline: TextBaseline.ideographic,
        children: [
          IconButton(
            tooltip: '${isMuted ? t.unmute : t.mute} ( Ctrl + M  )',
            icon: Icon(
              isMuted || volume == 0
                  ? Icons.volume_off_rounded
                  : volume < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              size: 20,
              color: color,
            ),
            onPressed: () {
              showControl();
              toggleMuteOrRestore();
            },
            style: ButtonStyle(overlayColor: overlayColor),
          ),
          Expanded(
            child: VolumeSlider(showControl: showControl, color: color),
          ),
          if (showVolumeText) const SizedBox(width: 8),
          if (showVolumeText) Text('${volume >= 100 ? '' : '  '}$volume'),
        ],
      ),
    );
  }
}
