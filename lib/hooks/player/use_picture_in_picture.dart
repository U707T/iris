import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/models/player.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/picture_in_picture.dart';
import 'package:iris/utils/platform.dart';
import 'package:provider/provider.dart';

/// 画中画在播放页的两件事:
///
/// 1. 把平台状态 (Android 系统小窗的进出、桌面小窗的开关) 镜像进
///    [PlayerUiStore.isPictureInPicture], 界面据此让位;
/// 2. Android: 播放条件变化时同步"离开应用要不要自动进小窗"。
///
/// 这里**不**负责进入 / 退出的手动入口 —— 那在「更多」菜单和小窗里的退出
/// 按钮, 走的是 [PictureInPicture.enter] / [PictureInPicture.exit]。
void usePictureInPicture({
  required FileItem? file,
  required bool hasOverlay,
}) {
  final context = useContext();

  final bool enabled =
      useAppStore().select(context, (state) => state.pictureInPicture);
  final bool isShortVideoMode =
      usePlayerUiStore().select(context, (state) => state.isShortVideoMode);
  final double aspectRatio =
      usePlayerUiStore().select(context, (state) => state.aspectRatio);

  final bool isPlaying =
      context.select<MediaPlayer, bool>((player) => player.isPlaying);
  final bool hasError =
      context.select<MediaPlayer, String?>((player) => player.error) != null;

  // 平台 -> store。原生回调可能在任意时刻到, 写 store 是最稳的落点:
  // 界面层只需要订阅一个 bool, 不用和通道打交道。
  useEffect(() {
    PictureInPicture.onModeChanged = (isInPictureInPicture) {
      usePlayerUiStore().updatePictureInPicture(isInPictureInPicture);
      if (!isInPictureInPicture) {
        // 从小窗回来: 控制栏应该立刻在, 而不是留一块空画面等用户点一下。
        usePlayerUiStore().updateIsShowControl(true);
      }
    };
    return () => PictureInPicture.onModeChanged = null;
  }, const []);

  // Android: 武装 / 解除自动进入。
  //
  // 条件由 [shouldArmAutoPictureInPicture] 统一判定 —— 测试盯的是那个纯函数,
  // 不是这里的某一行 effect。
  useEffect(() {
    if (!isAndroid) return null;

    unawaited(
      PictureInPicture.setAutoEnter(
        enabled: shouldArmAutoPictureInPicture(
          enabled: enabled,
          supported: PictureInPicture.isSupported,
          isVideo: file?.type == ContentType.video,
          isPlaying: isPlaying,
          isShortVideoMode: isShortVideoMode,
          hasError: hasError,
          hasOverlay: hasOverlay,
        ),
        aspectRatio: aspectRatio,
      ),
    );
    return null;
  }, [
    enabled,
    file?.type,
    isPlaying,
    isShortVideoMode,
    hasError,
    hasOverlay,
    aspectRatio,
  ]);
}
